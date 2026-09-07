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
            transferBar
        }.background(Design.canvas)
        .onAppear {
            browser.start(model: model, location: model.browserRequest)
            address = browser.currentURL.absoluteString
        }
        .onChange(of: browser.currentURL) { url in if !addressFocused { address = url.absoluteString } }
    }
    private var navigationBar: some View {
        VStack(spacing: Design.medium) {
            HStack(spacing: Design.small) {
                Button { browser.back() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).help(L("뒤로")).accessibilityLabel(L("MakerWorld 뒤로"))
                Button { browser.forward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward).help(L("앞으로")).accessibilityLabel(L("MakerWorld 앞으로"))
                Button { browser.load(MakerWorldBrowserPolicy.home) } label: { Image(systemName: "house") }.help(L("MakerWorld 홈"))
                HStack(spacing: Design.small) {
                    Image(systemName: addressFocused ? "magnifyingglass" : "globe").foregroundStyle(Design.secondary)
                    TextField(L("MakerWorld 검색 또는 모델 주소"), text: $address)
                        .textFieldStyle(.plain).focused($addressFocused)
                        .onSubmit { browser.navigate(address); addressFocused = false }
                    Button { browser.isLoading ? browser.stop() : browser.reload() } label: {
                        Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                    }.buttonStyle(.plain).help(browser.isLoading ? L("불러오기 중지") : L("페이지 새로고침"))
                }.padding(Design.medium).background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Design.controlRadius).stroke(Design.divider))
                Menu {
                    Button(L("현재 주소 복사")) { browser.copyAddress() }
                    Button(L("브라우저에서 열기")) { browser.openInBrowser() }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help(L("페이지 메뉴"))
            }.buttonStyle(.borderless)
            HStack {
                Label("MakerWorld", systemImage: "globe").font(Design.heading)
                Text(L("탐색 · 다운로드 · 내 보관함")).font(Design.caption).foregroundStyle(Design.secondary)
                Spacer()
                Label(L("자동 보관"), systemImage: "checkmark.shield").font(Design.caption).foregroundStyle(Design.accent)
                Toggle(L("보관된 파일 우선"), isOn: $browser.preferStored).toggleStyle(.switch).controlSize(.small).font(Design.caption)
                    .help(L("같은 출력 프로필을 이미 보관했다면 다운로드 없이 저장된 파일을 사용합니다. 최신 파일을 받으려면 끄세요."))
            }
        }.padding(.horizontal, Design.large).padding(.vertical, Design.medium)
    }
    private var transferBar: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            if let error = browser.transferError {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("다시 시도")) { browser.retryLatest() }.disabled(!browser.canRetry)
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
