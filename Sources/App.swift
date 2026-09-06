import SwiftUI

@main
struct PlateShelfApp: App {
    @StateObject private var model = LibraryViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: Design.windowMinWidth, minHeight: Design.windowMinHeight)
                .tint(Design.accent)
                .task { await model.start() }
                .onOpenURL { url in Task { await model.handle(url) } }
        }
        .defaultSize(width: Design.windowWidth, height: Design.windowHeight)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("import.files")) { model.chooseFiles() }.keyboardShortcut("o")
                Button(L("import.folder")) { model.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button(L("refresh")) { Task { await model.refresh() } }.keyboardShortcut("r")
            }
        }
        Settings { SettingsView(model: model).tint(Design.accent) }
    }
}
