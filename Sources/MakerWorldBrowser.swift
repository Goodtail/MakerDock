import AppKit
import Combine
import WebKit

@MainActor
final class MakerWorldBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, NSWindowDelegate {
    @Published var currentURL = MakerWorldBrowserPolicy.home
    @Published var title = "MakerWorld"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var pageError: String?
    @Published var context: CapturedMakerWorldSource?
    @Published var transferCount = 0
    @Published var transferMessage = AppIdentity.makerWorldCaptureEnabled ? L("웹에서 다운로드하거나 Studio로 열면 여기에 보관됩니다.") : ""
    @Published var collectionsMessage: String?
    private var collectionsRequestID: UUID?
    private var collectionsResolutionID: UUID?
    @Published var transferError: String?
    @Published var lastItemID: String?
    @Published var preferStored = true {
        didSet { UserDefaults.standard.set(preferStored, forKey: "browser.preferStored") }
    }
    private weak var model: LibraryViewModel?
    private var observations: [NSKeyValueObservation] = []
    private var popups: [ObjectIdentifier: (NSWindow, WKWebView)] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var activeLinks = Set<String>()
    private var lastHandoff: URL?
    private var started = false
    private var lastLocationID: UUID?
    lazy var webView: WKWebView = makeWebView()

    typealias CollectionsLookup = (WKWebView, String, @escaping (Result<Any, Error>) -> Void) -> Void
    private let collectionsLookup: CollectionsLookup
    init(collectionsLookup: @escaping CollectionsLookup = { view, script, completion in
        view.callAsyncJavaScript(script, arguments: ["timeoutMilliseconds": 12_000], in: nil, in: .page, completionHandler: completion)
    }) {
        self.collectionsLookup = collectionsLookup
        super.init()
        if UserDefaults.standard.object(forKey: "browser.preferStored") != nil {
            preferStored = UserDefaults.standard.bool(forKey: "browser.preferStored")
        }
    }
    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "MakerDock/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0")
        let content = configuration.userContentController
        if AppIdentity.makerWorldCaptureEnabled {
            content.add(WeakBrowserMessageHandler(self), name: "plateShelf")
        }
        for name in AppIdentity.makerWorldCaptureEnabled ? ["BrowserShared", "BrowserBridge"] : [] {
            if let url = Bundle.main.url(forResource: name, withExtension: "js"),
               let source = try? String(contentsOf: url, encoding: .utf8) {
                content.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            } else {
                pageError = L("MakerWorld 보관 연결을 불러오지 못했습니다. 앱을 다시 설치해 주세요.")
            }
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        observations = [
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.updateNavigation(view) }
            },
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.title = view.title ?? "MakerWorld" }
            },
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress; self?.isLoading = view.isLoading }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading; self?.updateNavigation(view) }
            }
        ]
        return view
    }
    func start(model: LibraryViewModel, location: BrowserLocation? = nil) {
        self.model = model
        if let location, location.id != lastLocationID {
            lastLocationID = location.id
            started = true
            if location.opensMyCollections { openMyCollections() } else { load(location.url) }
            return
        }
        guard !started else { return }
        started = true
        let restored = UserDefaults.standard.string(forKey: "browser.lastModel").flatMap(URL.init(string:))
        load(MakerWorldBrowserPolicy.isMakerWorld(restored) ? restored! : MakerWorldBrowserPolicy.home)
    }
    func load(_ url: URL) {
        guard MakerWorldBrowserPolicy.isMakerWorld(url) else { return }
        cancelCollectionsNavigation()
        pageError = nil
        webView.load(URLRequest(url: url))
    }
    func openMyCollections() {
        cancelCollectionsNavigation()
        collectionsRequestID = UUID()
        collectionsMessage = L("browser.collectionsOpening")
        pageError = nil
        if MakerWorldBrowserPolicy.isMakerWorld(webView.url) {
            if !webView.isLoading { resolveMyCollections() }
        } else {
            webView.load(URLRequest(url: MakerWorldBrowserPolicy.home))
        }
    }
    func cancelCollectionsNavigation() {
        collectionsRequestID = nil
        collectionsResolutionID = nil
        collectionsMessage = nil
    }
    private func resolveMyCollections() {
        guard let requestID = collectionsRequestID, collectionsResolutionID == nil,
              MakerWorldBrowserPolicy.isMakerWorld(webView.url), !webView.isLoading else { return }
        let resolutionID = UUID()
        collectionsResolutionID = resolutionID
        guard let scriptURL = Bundle.main.url(forResource: "CollectionsNavigation", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            collectionsMessage = L("browser.collectionsRetry")
            return
        }
        // Resolve only the site's own account navigation, on demand. Never read cookies,
        // tokens, private APIs, or another creator's collections link.
        collectionsLookup(webView, script) { [weak self] result in
            guard let self, self.collectionsRequestID == requestID,
                  self.collectionsResolutionID == resolutionID else { return }
            if case .success(let value) = result, let raw = value as? String,
               let url = URL(string: raw), MakerWorldBrowserPolicy.isCollections(url) {
                self.load(url.appendingPathComponent("models"))
            } else {
                self.collectionsMessage = L("browser.collectionsRetry")
                // Keep this attempt latched until a navigation or an explicit retry.
                // KVO updates on the same page must not repeatedly scan the document.
            }
        }
    }
    func navigate(_ text: String) {
        guard let url = MakerWorldBrowserPolicy.address(text) else {
            pageError = L("MakerWorld 주소나 검색어를 입력해 주세요."); return
        }
        load(url)
    }
    func back() { cancelCollectionsNavigation(); webView.goBack() }
    func forward() { cancelCollectionsNavigation(); webView.goForward() }
    func reload() { pageError = nil; webView.reload() }
    func stop() { cancelCollectionsNavigation(); webView.stopLoading() }
    func openInBrowser() { if ["https", "http"].contains(currentURL.scheme ?? "") { NSWorkspace.shared.open(currentURL) } }
    func copyAddress() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(currentURL.absoluteString, forType: .string) }
    var canRetry: Bool { lastHandoff != nil && transferCount == 0 }
    func retryLatest() { if let lastHandoff { receive(lastHandoff, force: true) } }
    private func updateNavigation(_ view: WKWebView) {
        guard view === webView else { return }
        if let url = view.url {
            currentURL = url
            if MakerWorldBrowserPolicy.modelKey(url.absoluteString) != MakerWorldBrowserPolicy.modelKey(context?.pageURL ?? "") ||
                MakerWorldBrowserPolicy.profileKey(url.absoluteString) != MakerWorldBrowserPolicy.profileKey(context?.profileURL) {
                context = nil
            }
            if let page = try? MakerWorldLinkPolicy.canonicalPage(url.absoluteString, includeProfile: true) {
                UserDefaults.standard.set(page.absoluteString, forKey: "browser.lastModel")
            } else if let page = try? MakerWorldLinkPolicy.canonicalPage(url.absoluteString, includeProfile: false) {
                UserDefaults.standard.set(page.absoluteString, forKey: "browser.lastModel")
            }
        }
        canGoBack = view.canGoBack; canGoForward = view.canGoForward
        if !view.isLoading { resolveMyCollections() }
    }
    private func trusted(_ frame: WKFrameInfo) -> Bool {
        frame.isMainFrame && frame.securityOrigin.protocol == "https" &&
        ["makerworld.com", "www.makerworld.com"].contains(frame.securityOrigin.host) &&
        [0, 443].contains(frame.securityOrigin.port)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard AppIdentity.makerWorldCaptureEnabled, trusted(message.frameInfo), let body = message.body as? [String: Any] else { return }
        if body["kind"] as? String == "handoff", let raw = body["url"] as? String, raw.utf8.count <= 65_536,
           let url = URL(string: raw), ["makerdock", "plateshelf"].contains(url.scheme ?? "") {
            receive(url)
        } else if body["kind"] as? String == "context", message.webView === webView {
            if let json = body["json"] as? String {
                let source = try? MakerWorldBrowserPolicy.context(json)
                // A delayed DOM report from a departed page must not label the new page.
                if MakerWorldBrowserPolicy.modelKey(source?.pageURL ?? "") == MakerWorldBrowserPolicy.modelKey(currentURL.absoluteString),
                   MakerWorldBrowserPolicy.profileKey(source?.profileURL) == MakerWorldBrowserPolicy.profileKey(currentURL.absoluteString) {
                    context = source
                }
            } else { context = nil }
        }
    }
    private func receive(_ url: URL, force: Bool = false) {
        guard AppIdentity.makerWorldCaptureEnabled, let model else { return }
        do { _ = try MakerWorldLinkPolicy.parse(url) }
        catch { transferError = error.localizedDescription; return }
        let key = MakerWorldLinkPolicy.sha256(Data(url.absoluteString.utf8))
        guard activeLinks.insert(key).inserted else { return }
        lastHandoff = url // Session memory only; never persist signed asset URLs.
        transferCount += 1; transferError = nil
        transferMessage = force ? L("최신 파일을 확인하고 있습니다…") : L("선택한 프로필을 보관하고 있습니다…")
        let reuse = preferStored
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeLinks.remove(key); self.transferCount -= 1 }
            do {
                let result = try await model.receiveBrowserDownload(url, preferStored: reuse, forceDownload: force)
                self.lastItemID = result.itemID
                self.transferMessage = result.usedLibrary
                    ? (result.openedStudio ? L("보관된 파일을 다운로드 없이 Studio에서 열었습니다.") : L("이미 보관한 프로필입니다. 저장된 파일을 사용합니다."))
                    : (result.openedStudio ? L("원본 링크와 함께 보관하고 Studio에서 열었습니다.") : L("3MF와 원본·프로필 정보를 보관했습니다."))
            } catch {
                self.transferError = error.localizedDescription
                self.transferMessage = L("파일을 보관하지 못했습니다.")
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["makerdock", "plateshelf", "bambustudioopen", "bambustudio"].contains(scheme) {
            decisionHandler(.cancel)
            if trusted(action.sourceFrame) {
                if AppIdentity.makerWorldCaptureEnabled { receive(url) }
                else if ["bambustudioopen", "bambustudio"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        if scheme == "https" || scheme == "http" {
            if AppIdentity.makerWorldCaptureEnabled, url.pathExtension.lowercased() == "3mf", trusted(action.sourceFrame),
               let link = try? MakerWorldBrowserPolicy.handoff(remote: url, name: url.lastPathComponent, page: action.sourceFrame.request.url) {
                decisionHandler(.cancel); receive(link); return
            }
            if action.shouldPerformDownload { decisionHandler(.download); return }
            // Auth redirects and embedded frames stay in WebKit. Ordinary outbound links use the system browser.
            let host = url.host?.lowercased() ?? ""
            let auth = host == "bambulab.com" || host.hasSuffix(".bambulab.com") || host == "accounts.google.com" || host == "appleid.apple.com"
            if webView === self.webView, action.targetFrame?.isMainFrame != false,
               !MakerWorldBrowserPolicy.isMakerWorld(url), !auth, action.navigationType == .linkActivated {
                decisionHandler(.cancel); NSWorkspace.shared.open(url); return
            }
            decisionHandler(.allow); return
        }
        if scheme == "about" || scheme == "blob" { decisionHandler(action.shouldPerformDownload ? .download : .allow); return }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { collectionsResolutionID = nil }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { pageError = nil; updateNavigation(webView) }
        else { resolveMyCollections() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    private func navigationFailed(_ view: WKWebView, _ error: Error) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        pageError = L("페이지를 불러오지 못했습니다. 연결을 확인한 뒤 다시 시도해 주세요.")
        isLoading = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { pageError = L("웹 화면이 종료되었습니다. 새로고침하면 다시 열립니다."); isLoading = false }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, MakerWorldBrowserPolicy.isMakerWorld(url) {
            self.webView.load(action.request); return nil
        }
        // A real child web view preserves window.opener for login providers; no cookies are copied out.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 760), configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("MakerWorld 로그인"); window.isReleasedWhenClosed = false
        window.contentView = popup; window.delegate = self; window.center()
        popups[ObjectIdentifier(popup)] = (window, popup)
        window.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) { popups[ObjectIdentifier(webView)]?.0.close() }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = popups.first(where: { $0.value.0 === window })?.key else { return }
        popups.removeValue(forKey: key)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = frame.securityOrigin.host
        alert.informativeText = String(message.prefix(2000)); alert.addButton(withTitle: L("확인"))
        if let window = webView.window { alert.beginSheetModal(for: window) { _ in completionHandler() } }
        else { completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(message.prefix(2000))
        alert.addButton(withTitle: L("확인")); alert.addButton(withTitle: L("취소"))
        if let window = webView.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) } }
        else { completionHandler(false) }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        if let window = webView.window { panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) } }
        else { completionHandler(nil) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Known 3MF handoffs use the bounded native importer. Other site files use an explicit Save dialog.
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        panel.title = L("파일 저장"); panel.canCreateDirectories = true
        guard let window = webView.window else { completionHandler(nil); return }
        panel.beginSheetModal(for: window) { [weak self] result in
            let destination = result == .OK ? panel.url : nil
            if let destination { self?.downloadDestinations[ObjectIdentifier(download)] = destination }
            completionHandler(destination)
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            transferMessage = String(format: L("%@을 저장했습니다."), String(file.lastPathComponent))
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        if (error as NSError).code != NSURLErrorCancelled { transferError = L("다운로드가 중단되었습니다. 다시 시도해 주세요.") }
    }
}

private final class WeakBrowserMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: MakerWorldBrowser?
    init(_ target: MakerWorldBrowser) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
