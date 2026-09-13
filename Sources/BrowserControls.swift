import AppKit
import WebKit

enum BrowserShortcut: Equatable {
    case newTab, closeTab, reopenTab, nextTab, previousTab, tab(Int)
    case address, reload, reloadFromOrigin, back, forward, find, findNext, findPrevious
    case zoomIn, zoomOut, resetZoom, escape

    // Physical key codes also work while a Korean, Japanese or Chinese input source is active.
    static func resolve(key: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        if flags == .control, key == 48 { return .nextTab }
        if flags == [.control, .shift], key == 48 { return .previousTab }
        if flags == [.command, .option] {
            if key == 124 { return .nextTab }
            if key == 123 { return .previousTab }
        }
        if flags.isEmpty, key == 53 { return .escape }
        if flags == [.command, .shift] {
            switch key {
            case 17: return .reopenTab
            case 30: return .nextTab
            case 33: return .previousTab
            case 15: return .reloadFromOrigin
            case 5: return .findPrevious
            case 24: return .zoomIn
            default: return nil
            }
        }
        guard flags == .command else { return nil }
        switch key {
        case 17: return .newTab
        case 13: return .closeTab
        case 37: return .address
        case 15: return .reload
        case 33: return .back
        case 30: return .forward
        case 3: return .find
        case 5: return .findNext
        case 24, 69: return .zoomIn
        case 27, 78: return .zoomOut
        case 29, 82: return .resetZoom
        default:
            let digits: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            return digits[key].map { .tab($0) }
        }
    }
}

/// Uses public NSView context-menu hooks, preserving WebKit's image, selection and editing actions.
final class MakerWorldWebView: WKWebView {
    var openLinkInTab: ((URL) -> Void)?
    private weak var openingMenu: NSMenu?
    private var menuRequest = UUID()

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard MakerWorldBrowserPolicy.isMakerWorld(url) else { return }
        openingMenu = menu
        let request = UUID(); menuRequest = request
        let document = url
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        // Inspect only the link under this user's right click, not the page or account data.
        callAsyncJavaScript("""
            let element = document.elementFromPoint(x, y);
            while (element?.shadowRoot?.elementFromPoint(x, y)) {
                const child = element.shadowRoot.elementFromPoint(x, y);
                if (child === element) break;
                element = child;
            }
            const link = element?.closest('a[href]');
            return link && !link.hasAttribute('download') ? link.href : null;
            """, arguments: ["x": point.x / pageZoom, "y": y / pageZoom], in: nil, in: .page) { [weak self, weak menu] result in
                guard let self, let menu, self.openingMenu === menu, self.menuRequest == request,
                      self.url == document, case .success(let value) = result,
                      let raw = value as? String, let url = Self.tabLink(raw) else { return }
                self.insertTabAction(into: menu, url: url)
            }
    }

    static func tabLink(_ raw: String) -> URL? {
        guard raw.utf8.count <= 4096, let url = URL(string: raw),
              MakerWorldBrowserPolicy.isMakerWorld(url), url.pathExtension.lowercased() != "3mf" else { return nil }
        return url
    }
    func insertTabAction(into menu: NSMenu, url: URL) {
        guard Self.tabLink(url.absoluteString) != nil else { return }
        let item = NSMenuItem(title: L("browser.openLinkInTab"), action: #selector(openContextLink(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = url
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(item, at: 0)
    }
    @objc private func openContextLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, Self.tabLink(url.absoluteString) != nil else { return }
        openLinkInTab?(url)
    }
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        openingMenu = nil; menuRequest = UUID()
        super.didCloseMenu(menu, with: event)
    }
}
