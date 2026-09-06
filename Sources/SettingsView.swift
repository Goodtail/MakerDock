import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: Design.large) {
            HStack { Text(L("settings")).font(Design.title); Spacer(); Button(L("done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: Design.large) {
                    section(L("settings.folders")) {
                        Text(L("settings.foldersDescription")).foregroundStyle(Design.secondary)
                        ForEach(model.preferences.folders, id: \.self) { path in
                            HStack { Image(systemName: "folder"); Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled); Spacer(); Button { model.preferences.folders.removeAll { $0 == path }; model.savePreferences() } label: { Image(systemName: "minus.circle") }.help(L("folder.unwatch")) }
                        }
                        Button(L("import.folder")) { model.chooseFolder() }
                        Toggle(L("settings.autoScan"), isOn: $model.preferences.automaticScan).onChange(of: model.preferences.automaticScan) { _ in model.savePreferences() }
                    }
                    Divider()
                    section(L("settings.studio")) {
                        HStack { Text(model.preferences.studioPath).lineLimit(1).truncationMode(.middle); Spacer(); Button(L("select")) { model.selectStudio() } }
                        Text(L("settings.workingCopy")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Divider()
                    section(L("settings.links")) {
                        Text(L("settings.linksDescription")).foregroundStyle(Design.secondary)
                        HStack { Button(L("link.register")) { model.registerLinks() }; Button(L("link.restore")) { model.restoreStudioLinks() } }
                    }
                    Divider()
                    section(L("settings.inbox")) {
                        Text(L("settings.inboxDescription")).foregroundStyle(Design.secondary)
                        HStack { Text(model.preferences.archivePath).font(Design.caption).lineLimit(2).textSelection(.enabled); Spacer(); Button(L("select")) { model.selectInbox() } }
                        Text(model.archiveStatus.isEmpty ? L("inbox.waiting") : model.archiveStatus).font(Design.caption).foregroundStyle(Design.secondary)
                        Text(L("settings.printerPending")).font(Design.caption).foregroundStyle(Design.warning)
                    }
                    Divider()
                    section(L("settings.storage")) {
                        Text(model.rootURL.path).font(Design.caption).textSelection(.enabled)
                        Button(L("storage.open")) { NSWorkspace.shared.open(model.rootURL) }
                        Text(L("settings.localOnly")).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                }
            }
        }.font(Design.body).padding(Design.xlarge).frame(width: Design.inspector * 2, height: Design.windowMinHeight)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.medium) { Text(title).font(Design.heading); content() }
    }
}
