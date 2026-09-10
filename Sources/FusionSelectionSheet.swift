import SwiftUI

struct FusionSelectionSheet: View {
    @ObservedObject var model: LibraryViewModel
    let selection: FusionSelection
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            Text(L("fusion.choose")).font(Design.detailTitle)
            Text(selection.title).font(Design.body).foregroundStyle(Design.secondary).lineLimit(2)
            ScrollView {
                LazyVStack(spacing: Design.small) {
                    ForEach(selection.meshes) { mesh in
                        Button { model.sendToFusion(mesh) } label: {
                            HStack(spacing: Design.medium) {
                                Image(systemName: "cube.transparent").foregroundStyle(Design.accent)
                                Text(mesh.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.forward.app").foregroundStyle(Design.secondary)
                            }.padding(Design.medium).background(Design.sidebarSurface, in: RoundedRectangle(cornerRadius: Design.imageRadius))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 300)
            Text(L("fusion.hint")).font(Design.caption).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(Design.large).frame(width: 460).background(Design.surface).foregroundStyle(Design.ink).font(Design.body)
    }
}
