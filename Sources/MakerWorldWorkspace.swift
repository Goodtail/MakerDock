import AppKit
import Combine
import WebKit

@MainActor
final class MakerWorldTab: Identifiable {
    let id = UUID()
    let section: ShelfFilter
    let browser: MakerWorldBrowser
    init(section: ShelfFilter, browser: MakerWorldBrowser) { self.section = section; self.browser = browser }
}

@MainActor
final class MakerWorldWorkspace: ObservableObject {
    @Published private(set) var tabs: [MakerWorldTab] = []
    @Published private(set) var section: ShelfFilter = .makerWorld
    @Published private var selections: [ShelfFilter: UUID] = [:]
    @Published private var closedPages: [(ShelfFilter, URL)] = []
    private var handledRequest: UUID?
    private weak var model: LibraryViewModel?
    private var shortcutMonitor: Any?
    private weak var browserWindow: NSWindow?
    private let makeBrowser: @MainActor (WKWebViewConfiguration?) -> MakerWorldBrowser
    init(makeBrowser: @escaping @MainActor (WKWebViewConfiguration?) -> MakerWorldBrowser = { MakerWorldBrowser(configuration: $0) }) {
        self.makeBrowser = makeBrowser
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event) == true ? nil : event
        }
    }
    deinit { if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) } }
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard model?.filter.isBrowser == true else { return false }
        if let window = active?.browser.webView.window { browserWindow = window }
        // A newly selected WKWebView may not be attached until SwiftUI's next render.
        // Keep the owning window stable so rapid tab changes followed by Cmd-W
        // cannot fall through to AppKit's Close Window command.
        guard let window = browserWindow, event.window === window,
              let action = BrowserShortcut.resolve(key: event.keyCode, modifiers: event.modifierFlags) else { return false }
        return handle(action)
    }
    // A local event monitor takes precedence over macOS's Close Window menu item.
    func handleTabShortcut(keyCode: UInt16, shifted: Bool) -> Bool {
        guard let action = BrowserShortcut.resolve(key: keyCode, modifiers: shifted ? [.command, .shift] : .command) else { return false }
        return handle(action)
    }
    @discardableResult
    func handle(_ action: BrowserShortcut) -> Bool {
        guard let browser = active?.browser else { return false }
        switch action {
        case .closeTab: if let active { close(active.id) }
        case .newTab: newTab(); active?.browser.focusAddress()
        case .reopenTab: reopen()
        case .nextTab: step(1)
        case .previousTab: step(-1)
        case .tab(let index):
            if index == 8, let last = visibleTabs.last { select(last.id) }
            else if visibleTabs.indices.contains(index) { select(visibleTabs[index].id) }
        case .address: browser.focusAddress()
        case .reload: browser.reload()
        case .reloadFromOrigin: browser.reload(fromOrigin: true)
        case .back: browser.back()
        case .forward: browser.forward()
        case .find: browser.showFind()
        case .findNext: browser.findNext()
        case .findPrevious: browser.findNext(backwards: true)
        case .zoomIn: browser.changeZoom(1)
        case .zoomOut: browser.changeZoom(-1)
        case .resetZoom: browser.resetZoom()
        case .escape:
            if browser.findVisible { browser.closeFind() }
            else if browser.isLoading { browser.stop() }
            else { return false }
        }
        return true
    }
    var visibleTabs: [MakerWorldTab] { tabs.filter { $0.section == section } }
    var active: MakerWorldTab? { visibleTabs.first { $0.id == selections[section] } ?? visibleTabs.first }
    var canReopen: Bool { closedPages.contains { $0.0 == section } }

    func show(model: LibraryViewModel) {
        self.model = model
        guard model.filter.isBrowser else { return }
        section = model.filter
        if let request = model.browserRequest, request.id != handledRequest {
            handledRequest = request.id
            if request.opensNewTab {
                if let existing = visibleTabs.first(where: { $0.browser.currentURL == request.url }) {
                    select(existing.id)
                } else { _ = add(in: section, request: URLRequest(url: request.url), foreground: true) }
                return
            }
            if active == nil { newTab(); return }
            if !request.restoresSession {
                if request.opensMyCollections { active?.browser.openMyCollections() }
                else { active?.browser.load(request.url) }
            }
        }
        if active == nil { newTab() }
    }
    func select(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.section == section else { return }
        selections[section] = id
    }
    func newTab() {
        let tab = add(in: section, request: nil, foreground: true)
        if section == .makerWorldCollections { tab.browser.openMyCollections() }
        else { tab.browser.load(MakerWorldBrowserPolicy.home) }
    }
    @discardableResult
    func add(in section: ShelfFilter, request: URLRequest?, configuration: WKWebViewConfiguration? = nil, foreground: Bool) -> MakerWorldTab {
        let browser = makeBrowser(configuration)
        let tab = MakerWorldTab(section: section, browser: browser)
        if let model { browser.attach(model: model) }
        browser.openTab = { [weak self, weak tab] request, configuration, foreground in
            guard let self, let tab else { return nil }
            let child = self.add(in: tab.section, request: request, configuration: configuration, foreground: foreground)
            return child.browser.webView
        }
        browser.closeTab = { [weak self, weak tab] in if let tab { self?.close(tab.id) } }
        tabs.append(tab)
        if foreground || selections[section] == nil { selections[section] = tab.id }
        if foreground { self.section = section; model?.filter = section }
        // WebKit performs the initial load itself for a window.open child.
        if configuration == nil, let request { browser.webView.load(request) }
        return tab
    }
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].browser.isTransferring else { return }
        let tab = tabs[index]
        if MakerWorldBrowserPolicy.isMakerWorld(tab.browser.currentURL) {
            closedPages.append((tab.section, tab.browser.currentURL))
            if closedPages.count > 20 { closedPages.removeFirst() }
        }
        let siblings = tabs.filter { $0.section == tab.section }
        let position = siblings.firstIndex(where: { $0.id == id }) ?? 0
        tab.browser.dispose(); tabs.remove(at: index)
        if selections[tab.section] == id {
            let remaining = tabs.filter { $0.section == tab.section }
            selections[tab.section] = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)].id
        }
        if active == nil { newTab() }
    }
    func reopen() {
        guard let index = closedPages.lastIndex(where: { $0.0 == section }) else { return }
        let page = closedPages.remove(at: index)
        _ = add(in: page.0, request: URLRequest(url: page.1), foreground: true)
    }
    func step(_ offset: Int) {
        guard let active, let index = visibleTabs.firstIndex(where: { $0.id == active.id }) else { return }
        select(visibleTabs[(index + offset + visibleTabs.count) % visibleTabs.count].id)
    }
}

import SwiftUI

struct MakerWorldWorkspaceView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var workspace: MakerWorldWorkspace
    @StateObject private var scroller = BrowserTabScroller()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { scroller.page(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!scroller.canGoBack)
                    .help(L("browser.scrollTabsLeft")).accessibilityLabel(L("browser.scrollTabsLeft"))
                GeometryReader { geometry in
                    let tabWidth = BrowserTabMetrics.width(available: geometry.size.width, count: workspace.visibleTabs.count)
                    BrowserTabStrip(scroller: scroller, ids: workspace.visibleTabs.map(\.id), selection: workspace.active?.id, tabWidth: tabWidth) {
                        HStack(spacing: BrowserTabMetrics.gap) {
                            ForEach(workspace.visibleTabs) { tab in
                                MakerWorldTabView(browser: tab.browser, selected: workspace.active?.id == tab.id, width: tabWidth,
                                                  select: { workspace.select(tab.id) }, close: { workspace.close(tab.id) })
                            }
                        }
                    }
                }.frame(minWidth: 0, maxWidth: .infinity).frame(height: 46)
                Button { scroller.page(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 28, height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!scroller.canGoForward)
                    .help(L("browser.scrollTabsRight")).accessibilityLabel(L("browser.scrollTabsRight"))
                Button { workspace.newTab() } label: {
                    Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L("browser.newTab") + " (⌘T)").accessibilityLabel(L("browser.newTab"))
                    .keyboardShortcut("t", modifiers: .command)
                Menu {
                    ForEach(workspace.visibleTabs) { tab in
                        BrowserTabMenuItem(browser: tab.browser, selected: workspace.active?.id == tab.id) { workspace.select(tab.id) }
                    }
                    Divider()
                    Button(L("browser.reopenTab")) { workspace.reopen() }.disabled(!workspace.canReopen)
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                    Button(L("browser.closeTab")) { if let tab = workspace.active { workspace.close(tab.id) } }
                        .disabled(workspace.active?.browser.isTransferring == true)
                        .keyboardShortcut("w", modifiers: .command)
                    Button(L("browser.nextTab")) { workspace.step(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                    Button(L("browser.previousTab")) { workspace.step(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                } label: { Image(systemName: "chevron.down").frame(width: 24, height: 32) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("browser.tabMenu")).accessibilityLabel(L("browser.tabMenu"))
            }.padding(.horizontal, Design.medium).background(Design.sidebarSurface)
            Divider()
            if let tab = workspace.active {
                MakerWorldView(model: model, browser: tab.browser).id(tab.id)
            }
        }.onAppear { workspace.show(model: model) }
    }
}

private struct MakerWorldTabView: View {
    @ObservedObject var browser: MakerWorldBrowser
    let selected: Bool
    let width: CGFloat
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 7) {
                    if browser.isLoading || browser.transferCount > 0 { ProgressView().controlSize(.mini) }
                    else { Image(systemName: browser.pageError == nil ? "globe" : "exclamationmark.circle") }
                    Text(browser.title).lineLimit(1).truncationMode(.tail)
                }.padding(.leading, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 32).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(browser.isTransferring).help(L("browser.closeTab")).accessibilityLabel(L("browser.closeTab"))
        }.font(Design.caption).frame(width: width)
            .foregroundStyle(selected ? Design.ink : Design.secondary)
            .background(selected ? Design.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Design.divider : Color.clear))
            .help(browser.title + "\n" + browser.currentURL.absoluteString)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BrowserTabMenuItem: View {
    @ObservedObject var browser: MakerWorldBrowser
    let selected: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            if selected { Label(browser.title, systemImage: "checkmark") }
            else { Text(browser.title) }
        }
    }
}
