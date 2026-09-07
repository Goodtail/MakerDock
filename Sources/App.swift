import SwiftUI
import PlateShelfCore

@main
struct PlateShelfApp: App {
    @AppStorage("MakerDockLanguage") private var language = ""
    @AppStorage("MakerDockAppearance") private var appearance = "system"
    @StateObject private var model = LibraryViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model).id(language)
                .environment(\.locale, ShelfLocalization.locale)
                .onChange(of: language) { _ in model.statusMessage = "" }
                .frame(minWidth: Design.windowMinWidth, minHeight: Design.windowMinHeight)
                .tint(Design.accent)
                .preferredColorScheme(ShelfAppearance.scheme(for: appearance))
                .task { ShelfAppearance.apply(appearance); await model.start() }
                .onChange(of: appearance) { ShelfAppearance.apply($0) }
                .onOpenURL { url in Task { await model.handle(url) } }
        }
        .defaultSize(width: Design.windowWidth, height: Design.windowHeight)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("import.files")) { model.chooseFiles() }.keyboardShortcut("o")
                Button(L("import.folder")) { model.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button(L("휴지통으로 이동")) {
                    if model.selectionMode { Task { _ = await model.applyBatch(.trash, ids: Set(model.selectedItems.map(\.id))) } }
                    else if let item = model.selected { Task { await model.trash(item) } }
                }.keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.isWorking || model.filter == .makerWorld || (model.selectionMode ? model.selectedItems.isEmpty : model.selected == nil) || model.filter == .trash)
            }
            CommandGroup(after: .toolbar) {
                Button(L("refresh")) {
                    if model.filter == .makerWorld { model.browserReloadRequest += 1 }
                    else { Task { await model.refresh() } }
                }.keyboardShortcut("r")
            }
        }
        Settings { SettingsView(model: model).id(language).environment(\.locale, ShelfLocalization.locale).tint(Design.accent).preferredColorScheme(ShelfAppearance.scheme(for: appearance)) }
    }
}
