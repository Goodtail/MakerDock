import SwiftUI
import PlateShelfCore

struct PlateZoomView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    let initialPlateID: String
    @State private var index = 0
    private var plate: PlateRecord? { item.plates.indices.contains(index) ? item.plates[index] : nil }
    var body: some View {
        VStack(spacing: Design.large) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.tiny) {
                    Text(plate.map(plateTitle) ?? L("plate")).font(Design.detailTitle)
                    Text(item.title).font(Design.body).foregroundStyle(Design.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(index + 1) / \(item.plates.count)").monospacedDigit().foregroundStyle(Design.secondary)
                Button(L("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ModelImage(url: model.imageURL(item, plate: plate)).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: Design.large) {
                Button { index -= 1 } label: { Label(L("plate.previous"), systemImage: "chevron.left") }.disabled(index == 0).keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                EstimateLabel(estimate: plate.flatMap { model.displayedEstimate(item, plate: $0) }, missing: L("개별 시간 미제공"))
                if let grams = plate?.weightGrams { Text(weightText(grams)).monospacedDigit() }
                Spacer()
                Button { index += 1 } label: { Label(L("plate.next"), systemImage: "chevron.right") }.disabled(index + 1 >= item.plates.count).keyboardShortcut(.rightArrow, modifiers: [])
            }.font(Design.body)
            if item.plates.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Design.small) {
                        ForEach(Array(item.plates.enumerated()), id: \.element.id) { offset, p in
                            Button { index = offset } label: {
                                VStack(spacing: Design.tiny) {
                                    ModelImage(url: model.imageURL(item, plate: p)).frame(width: Design.plateThumbnail, height: Design.hero)
                                    Text("\(offset + 1)").font(Design.caption)
                                }.padding(Design.tiny).overlay(RoundedRectangle(cornerRadius: Design.imageRadius).stroke(index == offset ? Design.accent : Color.clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(plateTitle(p))
                        }
                    }.padding(Design.tiny)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.padding(Design.large).frame(width: Design.zoomWidth, height: Design.zoomHeight).background(Design.surface).foregroundStyle(Design.ink)
            .onAppear { index = item.plates.firstIndex { $0.id == initialPlateID } ?? 0 }
    }
}

struct SourceLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    @State private var page = ""
    @State private var profile = ""
    @State private var isSaving = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: Design.large) {
            Text(L("source.edit")).font(Design.detailTitle)
            Text(L("source.linkExplanation")).font(Design.body).foregroundStyle(Design.secondary)
            TextField(L("source.placeholder"), text: $page).textFieldStyle(.roundedBorder)
            TextField(L("source.profilePlaceholder"), text: $profile).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(Design.caption).foregroundStyle(Design.warning) }
            HStack {
                Spacer()
                Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button(L("save")) {
                    isSaving = true
                    Task {
                        do { try await model.saveSource(item, page: page, profile: profile); dismiss() }
                        catch { self.error = error.localizedDescription }
                        isSaving = false
                    }
                }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(Color.white).keyboardShortcut(.defaultAction).disabled(isSaving || page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(Design.large).frame(width: Design.zoomWidth - Design.inspector)
            .onAppear { page = item.makerWorldSource?.pageURL ?? ""; profile = item.makerWorldSource?.profileURL ?? "" }
    }
}
