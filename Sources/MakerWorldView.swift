import SwiftUI
import WebKit

struct MakerWorldView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var browser: MakerWorldBrowser
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    private var saved: ShelfItem? { model.savedProfile(browser.context?.profileURL) }
    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            if browser.freshDownload {
                HStack(spacing: Design.small) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Design.accent)
                    Text(L("browser.freshHint")).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L("취소")) { browser.freshDownload = false }
                }.font(Design.caption).padding(Design.medium).background(Design.surface)
            }
            if let message = browser.collectionsMessage {
                HStack(spacing: Design.small) {
                    Image(systemName: "square.stack").foregroundStyle(Design.accent)
                    Text(message).font(Design.caption)
                    Spacer()
                    Button(L("다시 시도")) { browser.openMyCollections() }
                }.padding(Design.medium).background(Design.surface)
            }
            if let source = browser.context {
                HStack(spacing: Design.medium) {
                    Image(systemName: saved == nil ? "cube" : "checkmark.circle.fill").foregroundStyle(Design.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.title ?? browser.title).font(Design.value).lineLimit(1)
                        HStack(spacing: Design.small) {
                            if let profile = source.profileTitle { Text(profile).lineLimit(1) }
                            if let count = source.plateCount { Text(String(format: L("%@ 플레이트"), String(count))).fixedSize() }
                            if let seconds = source.estimatedSeconds { Text(timeText(seconds)).fixedSize() }
                        }.font(Design.caption).foregroundStyle(Design.secondary)
                        if source.profileTitle == nil, source.plateCount == nil, source.estimatedSeconds == nil,
                           let snapshot = saved?.makerWorldSource {
                            HStack(spacing: Design.small) {
                                Text(L("보관 당시")).fixedSize()
                                if let profile = snapshot.profileTitle { Text(profile).lineLimit(1) }
                                if let count = snapshot.plateCount { Text(String(format: L("%@ 플레이트"), String(count))).fixedSize() }
                                if let seconds = snapshot.estimatedSeconds { Text(timeText(seconds)).fixedSize() }
                            }.font(Design.caption).foregroundStyle(Design.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let saved {
                        Text(L("보관된 프로필")).font(Design.caption).foregroundStyle(Design.accent)
                        Button(L("보관함에서 보기")) { model.showLibraryItem(saved.id) }
                        Button(L("저장된 파일 열기")) { model.openInStudio(saved) }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(Color.white)
                    } else {
                        Text(L("웹에서 3MF를 받으면 자동 보관")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                }.padding(.horizontal, Design.large).padding(.vertical, Design.medium).background(Design.surface)
            }
            ZStack(alignment: .top) {
                MakerWorldWebSurface(browser: browser)
                if browser.isLoading { ProgressView(value: browser.progress).progressViewStyle(.linear).tint(Design.accent) }
                if let error = browser.pageError {
                    VStack(spacing: Design.regular) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(Design.secondary)
                        Text(error).multilineTextAlignment(.center)
                        HStack {
                            Button(L("다시 불러오기")) { browser.reload() }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(Color.white)
                            Button(L("브라우저에서 열기")) { browser.openInBrowser() }
                        }
                    }.padding(Design.xlarge).frame(maxWidth: 440)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.cardRadius))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !browser.transferMessage.isEmpty || browser.transferError != nil { transferBar }
        }.background(Design.canvas)
        .onAppear {
            browser.attach(model: model)
            address = browser.currentURL.absoluteString
        }
        .onChange(of: browser.currentURL) { url in if !addressFocused { address = url.absoluteString } }
    }
    private var navigationBar: some View {
        VStack(spacing: Design.medium) {
            HStack(spacing: Design.small) {
                Button { browser.back() } label: { navigationIcon("chevron.left") }.disabled(!browser.canGoBack).keyboardShortcut("[", modifiers: .command).help(L("뒤로") + " (⌘[)").accessibilityLabel(L("MakerWorld 뒤로"))
                Button { browser.forward() } label: { navigationIcon("chevron.right") }.disabled(!browser.canGoForward).keyboardShortcut("]", modifiers: .command).help(L("앞으로") + " (⌘])").accessibilityLabel(L("MakerWorld 앞으로"))
                Button { browser.load(MakerWorldBrowserPolicy.home) } label: { navigationIcon("house") }.help(L("MakerWorld 홈"))
                HStack(spacing: Design.small) {
                    Image(systemName: addressFocused ? "magnifyingglass" : "globe").foregroundStyle(Design.secondary)
                    TextField(L("MakerWorld 검색 또는 모델 주소"), text: $address)
                        .textFieldStyle(.plain).focused($addressFocused)
                        .onSubmit { browser.navigate(address); addressFocused = false }
                    Button { browser.isLoading ? browser.stop() : browser.reload() } label: {
                        Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise").frame(width: 30, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(browser.isLoading ? L("불러오기 중지") : L("페이지 새로고침"))
                }.padding(.horizontal, Design.medium).padding(.vertical, 4).background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Design.controlRadius).stroke(Design.divider))
                Menu {
                    Button(L("현재 주소 복사")) { browser.copyAddress() }
                    Button(L("브라우저에서 열기")) { browser.openInBrowser() }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help(L("페이지 메뉴"))
            }.buttonStyle(.borderless)
            HStack {
                Label("MakerWorld", systemImage: "globe").font(Design.heading)
                Spacer()
                Button { model.showMyCollections() } label: {
                    Label(L("browser.myCollections"), systemImage: "square.stack")
                }.buttonStyle(.borderless)
                Toggle(L("보관된 파일 우선"), isOn: $browser.preferStored).toggleStyle(.switch).controlSize(.small).font(Design.caption)
                    .help(L("browser.reuseHelp"))
                Button { browser.freshDownload.toggle() } label: {
                    Label(L("browser.freshDownload"), systemImage: "arrow.down.circle")
                }.buttonStyle(.bordered).disabled(browser.transferCount > 0)
                    .help(L("browser.freshHint"))
            }
        }.padding(.horizontal, Design.medium).padding(.vertical, Design.small)
            .background {
                Button("") { address = browser.currentURL.absoluteString; addressFocused = true }
                    .keyboardShortcut("l", modifiers: .command).hidden()
            }
    }
    private func navigationIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .medium))
            .frame(width: 38, height: 38).contentShape(Rectangle())
            .background(Design.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    private var transferBar: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            if let error = browser.transferError {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if browser.canRetry { Button(L("다시 시도")) { browser.retryLatest() } }
                    Button { browser.transferError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.foregroundStyle(Design.warning)
            }
            HStack(spacing: Design.small) {
                if browser.transferCount > 0 { ProgressView().controlSize(.small) }
                else { Image(systemName: "tray.and.arrow.down").foregroundStyle(Design.accent) }
                Text(browser.transferMessage).lineLimit(2)
                Spacer()
                if let id = browser.lastItemID {
                    Button(L("방금 보관한 모델")) { model.showLibraryItem(id) }
                }
                if browser.canRetry {
                    Menu {
                        Button(L("마지막 파일을 최신 버전으로 다시 받기")) { browser.retryLatest() }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }
            }
        }.font(Design.caption).foregroundStyle(Design.secondary)
            .padding(Design.medium).background(Design.surface).overlay(alignment: .top) { Divider() }
    }
}

private struct MakerWorldWebSurface: NSViewRepresentable {
    @ObservedObject var browser: MakerWorldBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
