import AppKit
import SwiftUI

enum BrowserTabMetrics {
    static let gap: CGFloat = 4
    static let minimumWidth: CGFloat = 104
    static let maximumWidth: CGFloat = 194
    static func width(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maximumWidth }
        return max(minimumWidth, min(maximumWidth, (available - CGFloat(count - 1) * gap) / CGFloat(count)))
    }
}

@MainActor
final class BrowserTabScroller: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    weak var view: BrowserTabScrollView?
    func update() {
        guard let view else { return }
        let back = view.contentView.bounds.minX > 1
        let forward = view.contentView.bounds.minX < view.maximumOffset - 1
        if canGoBack != back { canGoBack = back }
        if canGoForward != forward { canGoForward = forward }
    }
    func page(_ direction: Int) { view?.move(to: (view?.contentView.bounds.minX ?? 0) + CGFloat(direction) * max(198, (view?.contentSize.width ?? 0) * 0.8)) }
}

final class BrowserTabScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    var selectedIndex: Int?
    var tabWidth = BrowserTabMetrics.maximumWidth
    private var lastViewportWidth: CGFloat = 0
    var maximumOffset: CGFloat { max(0, (documentView?.frame.width ?? 0) - contentSize.width) }
    func move(to offset: CGFloat) {
        contentView.scroll(to: NSPoint(x: min(maximumOffset, max(0, offset)), y: 0))
        reflectScrolledClipView(contentView)
        onScroll?()
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        move(to: contentView.bounds.minX - delta * (event.hasPreciseScrollingDeltas ? 1 : 24))
    }
    func revealSelection() {
        guard let index = selectedIndex, contentSize.width > 0 else { return }
        let start = CGFloat(index) * (tabWidth + BrowserTabMetrics.gap)
        let end = start + tabWidth
        if start < contentView.bounds.minX { move(to: start) }
        else if end > contentView.bounds.maxX { move(to: end - contentSize.width) }
        else { move(to: contentView.bounds.minX) }
    }
    override func layout() {
        super.layout()
        if abs(lastViewportWidth - contentSize.width) > 0.5 {
            lastViewportWidth = contentSize.width
            revealSelection()
        }
        onScroll?()
    }
}

struct BrowserTabStrip<Content: View>: NSViewRepresentable {
    @ObservedObject var scroller: BrowserTabScroller
    let ids: [UUID]
    let selection: UUID?
    let tabWidth: CGFloat
    @ViewBuilder var content: () -> Content
    final class Coordinator {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        var selection: UUID?
        var tabWidth: CGFloat = 0
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> BrowserTabScrollView {
        let view = BrowserTabScrollView()
        view.drawsBackground = false
        view.hasHorizontalScroller = false; view.hasVerticalScroller = false
        view.autohidesScrollers = true; view.scrollerStyle = .overlay
        view.horizontalScrollElasticity = .none; view.verticalScrollElasticity = .none
        context.coordinator.host.sizingOptions = []
        view.documentView = context.coordinator.host
        view.contentView.postsBoundsChangedNotifications = true
        view.onScroll = { [weak scroller] in DispatchQueue.main.async { scroller?.update() } }
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: view.contentView, queue: .main) { [weak view] _ in view?.onScroll?() }
        scroller.view = view
        return view
    }
    func updateNSView(_ view: BrowserTabScrollView, context: Context) {
        let width = max(0, CGFloat(ids.count) * (tabWidth + BrowserTabMetrics.gap) - BrowserTabMetrics.gap)
        context.coordinator.host.rootView = AnyView(content().frame(width: width, height: 46, alignment: .leading))
        context.coordinator.host.setFrameSize(NSSize(width: width, height: 46))
        view.selectedIndex = selection.flatMap { ids.firstIndex(of: $0) }
        let changed = context.coordinator.selection != selection || context.coordinator.tabWidth != tabWidth
        view.tabWidth = tabWidth
        context.coordinator.tabWidth = tabWidth
        context.coordinator.selection = selection
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if changed { view.revealSelection() }
            else { view.move(to: view.contentView.bounds.minX) }
        }
    }
}
