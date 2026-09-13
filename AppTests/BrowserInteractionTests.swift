import XCTest
import AppKit
import WebKit
@testable import PlateShelf

private final class BrowserFixtureLoad: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}

final class BrowserInteractionTests: XCTestCase {
    func testChromeShortcutModifiersAndInputSourceIndependentKeys() {
        XCTAssertEqual(BrowserShortcut.resolve(key: 48, modifiers: .control), .nextTab)
        XCTAssertEqual(BrowserShortcut.resolve(key: 48, modifiers: [.control, .shift]), .previousTab)
        XCTAssertEqual(BrowserShortcut.resolve(key: 124, modifiers: [.command, .option]), .nextTab)
        XCTAssertEqual(BrowserShortcut.resolve(key: 123, modifiers: [.command, .option]), .previousTab)
        XCTAssertEqual(BrowserShortcut.resolve(key: 25, modifiers: [.command, .capsLock]), .tab(8))
        XCTAssertEqual(BrowserShortcut.resolve(key: 15, modifiers: [.command, .shift]), .reloadFromOrigin)
        XCTAssertEqual(BrowserShortcut.resolve(key: 5, modifiers: [.command, .shift]), .findPrevious)
        XCTAssertEqual(BrowserShortcut.resolve(key: 24, modifiers: [.command, .shift]), .zoomIn)
        XCTAssertNil(BrowserShortcut.resolve(key: 13, modifiers: [.command, .shift]), "Leave Close Window to macOS")
        XCTAssertNil(BrowserShortcut.resolve(key: 48, modifiers: []), "Do not consume regular tab focus navigation")
        XCTAssertNil(BrowserShortcut.resolve(key: 123, modifiers: .command), "Do not steal text caret movement")
        XCTAssertNil(BrowserShortcut.resolve(key: 17, modifiers: [.command, .control]))
    }

    @MainActor func testManyTabsSelectByNumberWrapAndProtectImports() throws {
        let workspace = MakerWorldWorkspace { _ in
            let browser = MakerWorldBrowser(); browser.webView = RecordingBrowserWebView(); return browser
        }
        for number in 1...24 {
            workspace.add(in: .makerWorld, request: URLRequest(url: URL(string: "https://makerworld.com/en/models/\(number)")!), foreground: false)
        }
        let first = try XCTUnwrap(workspace.active)
        XCTAssertTrue(workspace.handle(.tab(8)))
        XCTAssertEqual(workspace.active?.id, workspace.visibleTabs.last?.id)
        workspace.handle(.nextTab)
        XCTAssertEqual(workspace.active?.id, first.id)
        workspace.handle(.previousTab)
        XCTAssertEqual(workspace.active?.id, workspace.visibleTabs.last?.id)
        workspace.handle(.tab(3))
        XCTAssertEqual(workspace.active?.id, workspace.visibleTabs[3].id)
        workspace.active?.browser.transferCount = 1
        workspace.handle(.closeTab)
        XCTAssertEqual(workspace.visibleTabs.count, 24)
        workspace.active?.browser.transferCount = 0
        workspace.handle(.closeTab)
        XCTAssertEqual(workspace.visibleTabs.count, 23)
        workspace.handle(.address)
        XCTAssertEqual(workspace.active?.browser.addressFocusRequest, 1)
        XCTAssertFalse(workspace.handle(.escape), "A website must keep Escape when no browser UI needs it")
    }

    @MainActor func testRapidTabSwitchThenCloseNeverFallsThroughToCloseWindow() throws {
        let model = LibraryViewModel(rootOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: model.rootURL) }
        let workspace = MakerWorldWorkspace { _ in
            let browser = MakerWorldBrowser(); browser.webView = RecordingBrowserWebView(); return browser
        }
        model.selectFilter(.makerWorld); workspace.show(model: model)
        let first = try XCTUnwrap(workspace.active)
        workspace.add(in: .makerWorld, request: nil, foreground: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = first.browser.webView
        defer { window.close() }
        func event(_ key: UInt16, windowNumber: Int? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: windowNumber ?? window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
        }
        XCTAssertTrue(workspace.handleKeyEvent(try event(25))) // Cmd-9
        XCTAssertNil(workspace.active?.browser.webView.window, "The next tab has not been attached by SwiftUI yet")
        XCTAssertTrue(workspace.handleKeyEvent(try event(13))) // Cmd-W
        XCTAssertEqual(workspace.visibleTabs.count, 1)
        XCTAssertEqual(workspace.active?.id, first.id)
        XCTAssertFalse(workspace.handleKeyEvent(try event(13, windowNumber: -1)))
        model.selectFilter(.all)
        XCTAssertFalse(workspace.handleKeyEvent(try event(13)), "Library window commands must stay native")
    }

    func testTabsShareAvailableWidthBeforeOverflowing() {
        XCTAssertEqual(BrowserTabMetrics.width(available: 1000, count: 1), 194)
        let width = BrowserTabMetrics.width(available: 1000, count: 7)
        XCTAssertEqual(width * 7 + 6 * BrowserTabMetrics.gap, 1000, accuracy: 0.01)
        XCTAssertEqual(BrowserTabMetrics.width(available: 1000, count: 24), 104)
        XCTAssertEqual(BrowserTabMetrics.width(available: 0, count: 0), 194)
    }

    @MainActor func testTabStripRevealsLastTabClampsAndAllowsWheelScrolling() throws {
        let scroll = BrowserTabScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 46))
        scroll.hasHorizontalScroller = true; scroll.scrollerStyle = .overlay
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 24 * 198 - 4, height: 46))
        scroll.selectedIndex = 23
        scroll.layoutSubtreeIfNeeded(); scroll.revealSelection()
        XCTAssertEqual(scroll.contentView.bounds.minX, scroll.maximumOffset, accuracy: 1)
        scroll.move(to: -200)
        XCTAssertEqual(scroll.contentView.bounds.minX, 0)
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, "Manual scrolling must not snap back to the selected tab")
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:)))
        scroll.scrollWheel(with: event)
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0, "A vertical wheel must scroll the tabs horizontally")
        scroll.move(to: 100_000)
        XCTAssertEqual(scroll.contentView.bounds.minX, scroll.maximumOffset, accuracy: 1)
        scroll.setFrameSize(NSSize(width: 420, height: 46)); scroll.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.maxX, 24 * 198 - 4 - 1, "Resizing keeps the active tab visible")
        scroll.documentView?.setFrameSize(NSSize(width: 194, height: 46)); scroll.selectedIndex = 0; scroll.revealSelection()
        XCTAssertEqual(scroll.contentView.bounds.minX, 0)
        XCTAssertEqual(scroll.maximumOffset, 0)
    }

    @MainActor func testNativeContextMenuPreservesItemsAndOpensBackgroundTab() async throws {
        let browser = MakerWorldBrowser()
        let view = try XCTUnwrap(browser.webView as? MakerWorldWebView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close(); browser.dispose() }
        let loaded = expectation(description: "Local link fixture loaded")
        let delegate = BrowserFixtureLoad(loaded); view.navigationDelegate = delegate
        view.loadHTMLString("<a href='https://makerworld.com/en/models/123-hook' style='position:absolute;left:20px;top:20px;width:300px;height:80px'>Open model</a>", baseURL: MakerWorldBrowserPolicy.home)
        await fulfillment(of: [loaded], timeout: 10)
        let point = view.convert(NSPoint(x: 40, y: view.isFlipped ? 40 : view.bounds.height - 40), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = NSMenu(); menu.addItem(withTitle: "Existing WebKit action", action: nil, keyEquivalent: "")
        view.willOpenMenu(menu, with: event)
        for _ in 0..<60 where menu.items.count == 1 { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items.last?.title, "Existing WebKit action")
        let item = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(item.title, L("browser.openLinkInTab"))
        var opened: URLRequest?; var foreground: Bool?
        browser.openTab = { request, _, isForeground in opened = request; foreground = isForeground; return nil }
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        XCTAssertEqual(opened?.url?.path, "/en/models/123-hook")
        XCTAssertEqual(foreground, false)
        XCTAssertEqual(view.url, MakerWorldBrowserPolicy.home)
        view.didCloseMenu(menu, with: event)
        // A right click away from a link leaves the native context menu untouched.
        let blank = NSMenu(); blank.addItem(withTitle: "Native", action: nil, keyEquivalent: "")
        let away = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: 500, y: 250), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
        view.willOpenMenu(blank, with: away)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(blank.items.count, 1)
        withExtendedLifetime(delegate) {}
    }

    @MainActor func testContextLinkValidationExcludesDownloadsAndForeignSchemes() {
        XCTAssertNotNil(MakerWorldWebView.tabLink("https://makerworld.com/en/models/123#profileId-456"))
        for raw in ["javascript:alert(1)", "file:///private/tmp/test", "https://makerworld.com.evil.test/models/1", "https://user@makerworld.com/models/1", "https://makerworld.com/model.3MF"] {
            XCTAssertNil(MakerWorldWebView.tabLink(raw), raw)
        }
    }

    @MainActor func testFindUsesWebKitAndZoomStaysWithinBounds() async throws {
        let browser = MakerWorldBrowser()
        let view = browser.webView
        let loaded = expectation(description: "Local find fixture loaded")
        let delegate = BrowserFixtureLoad(loaded); view.navigationDelegate = delegate
        view.loadHTMLString("<p>MakerDock printing plans</p><p>MakerDock models</p>", baseURL: MakerWorldBrowserPolicy.home)
        await fulfillment(of: [loaded], timeout: 10)
        browser.findText = "MakerDock"; browser.findNext()
        for _ in 0..<60 where browser.findHasMatch == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(browser.findHasMatch, true)
        browser.findText = "unmatched text"; browser.findHasMatch = nil; browser.findNext(backwards: true)
        for _ in 0..<60 where browser.findHasMatch == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(browser.findHasMatch, false)
        browser.closeFind(); XCTAssertFalse(browser.findVisible); XCTAssertNil(browser.findHasMatch)
        for _ in 0..<25 { browser.changeZoom(1) }
        XCTAssertEqual(browser.zoom, 3); XCTAssertEqual(view.pageZoom, 3)
        for _ in 0..<25 { browser.changeZoom(-1) }
        XCTAssertEqual(browser.zoom, 0.5); XCTAssertEqual(view.pageZoom, 0.5)
        browser.resetZoom(); XCTAssertEqual(view.pageZoom, 1)
        browser.dispose(); withExtendedLifetime(delegate) {}
    }
}
