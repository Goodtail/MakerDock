import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("MakerDockLanguage") private var language = ""
    @AppStorage("MakerDockAppearance") private var appearance = "system"
    @ObservedObject var model: LibraryViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: Design.large) {
            HStack { Text(L("settings")).font(Design.title); Spacer(); Button(L("done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: Design.large) {
                    section(L("appearance.title")) {
                        Picker(L("appearance.title"), selection: $appearance) {
                            ForEach(ShelfAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                        }.pickerStyle(.segmented)
                        Text(L("appearance.description")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Divider()
                    section(L("settings.language")) {
                        Picker(L("settings.language"), selection: $language) {
                            Text(L("language.system")).tag("")
                            Text("한국어").tag("ko")
                            Text("English").tag("en")
                            Text("日本語").tag("ja")
                            Text("简体中文").tag("zh-Hans")
                        }
                    }
                    Divider()
                    section(L("내 프린터 · 예상 시간")) {
                        Picker(L("프린터 / 노즐"), selection: $model.preferences.printerPreset) {
                            Text(L("선택 안 함")).tag("")
                            ForEach(model.printerCatalog?.machines ?? []) { Text($0.name).tag($0.name) }
                        }.onChange(of: model.preferences.printerPreset) { _ in model.configurePrinter() }
                        Picker(L("출력 품질"), selection: $model.preferences.printerProcess) {
                            Text(L("출력 품질 선택")).tag("")
                            ForEach(model.compatiblePrinterProcesses) { Text($0.name).tag($0.name) }
                        }.onChange(of: model.preferences.printerProcess) { _ in model.configurePrinter() }
                        Button(L("Studio에서 선택한 프린터 가져오기")) { model.configurePrinter(importFromStudio: true) }
                        Text(L("상세 화면에서 선택한 프린터와 출력 품질로 시간을 계산합니다. 재료·플레이트 배치·개별 오브젝트 설정은 파일에 저장된 값을 사용합니다."))
                            .font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Divider()
                    section(L("settings.folders")) {
                        Text(L("settings.foldersDescription")).foregroundStyle(Design.secondary)
                        ForEach(model.preferences.folders, id: \.self) { path in
                            HStack { Image(systemName: "folder"); Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled); Spacer(); Button { model.preferences.folders.removeAll { $0 == path }; model.savePreferences() } label: { Image(systemName: "minus.circle") }.help(L("folder.unwatch")) }
                        }
                        Button(L("import.folder")) { model.chooseFolder() }
                        Toggle(L("settings.autoScan"), isOn: $model.preferences.automaticScan).onChange(of: model.preferences.automaticScan) { _ in model.savePreferences() }
                    }
                    Divider()
                    section(L("출력 완료 파일 정리")) {
                        Picker(L("기본 이동 위치"), selection: $model.preferences.completedMoveMode) {
                            Text(L("원본 폴더 안의 출력 완료 폴더")).tag("source")
                            Text(L("지정한 한 폴더로 모으기")).tag("custom")
                            Text(L("앱 보관함 안에서만 이동")).tag("library")
                        }.onChange(of: model.preferences.completedMoveMode) { _ in model.savePreferences() }
                        if model.preferences.completedMoveMode == "custom" {
                            HStack {
                                Text(model.preferences.completedFolder.isEmpty ? L("완료 폴더를 선택해 주세요") : model.preferences.completedFolder).font(Design.caption).lineLimit(2).textSelection(.enabled)
                                Spacer(); Button(L("폴더 선택…")) { model.selectCompletedFolder() }
                            }
                        }
                        Text(L("완료 기록을 저장하기 전에 실제 이동 경로를 확인하고 바꿀 수 있습니다.")).font(Design.caption).foregroundStyle(Design.secondary)
                        Text(L("실제 출력이 끝나면 상세 화면에서 완료로 표시해 주세요.")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Divider()
                    section(L("settings.studio")) {
                        HStack { Text(model.preferences.studioPath).lineLimit(1).truncationMode(.middle); Spacer(); Button(L("select")) { model.selectStudio() } }
                        Text(L("settings.workingCopy")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Divider()
                    if AppIdentity.makerWorldIntegrationEnabled { section(L("settings.links")) {
                        Text(L("settings.linksDescription")).foregroundStyle(Design.secondary)
                        HStack { Button(L("link.register")) { model.registerLinks() }; Button(L("link.restore")) { model.restoreStudioLinks() } }
                    }
                    Divider()
                    }
                    section(L("settings.storage")) {
                        Text(model.rootURL.path).font(Design.caption).textSelection(.enabled)
                        Button(L("storage.open")) { NSWorkspace.shared.open(model.rootURL) }
                        Text(L("settings.localOnly")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                }
            }
        }.font(Design.body).padding(Design.xlarge).frame(width: Design.inspector * 2, height: Design.windowMinHeight)
            .background(Design.surface).foregroundStyle(Design.ink)
            .preferredColorScheme(ShelfAppearance.scheme(for: appearance))
            .onAppear { ShelfAppearance.apply(appearance); model.configurePrinter() }
            .onChange(of: appearance) { ShelfAppearance.apply($0) }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.medium) { Text(title).font(Design.heading); content() }
    }
}
