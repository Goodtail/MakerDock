import SwiftUI
import PlateShelfCore

enum LibraryBatchAction { case category(String?), trash, restore, favorite(Bool) }
struct BatchResult { var succeeded: Set<String> = []; var errors: [String] = [] }
struct BatchPrintDraft: Identifiable {
    let item: ShelfItem
    var details: PrintDetailsDraft
    var id: String { item.id }
}

extension LibraryViewModel {
    var selectedItems: [ShelfItem] { visibleItems.filter { selectedIDs.contains($0.id) } }
    func selectItem(_ item: ShelfItem) {
        if selectionMode {
            if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
        } else { selectionID = item.id }
    }
    func endSelection() { selectionMode = false; selectedIDs = [] }
    func selectAllVisible() { selectedIDs = Set(visibleItems.map(\.id)) }
    func pruneSelection() { selectedIDs.formIntersection(Set(visibleItems.map(\.id))) }

    func applyBatch(_ action: LibraryBatchAction, ids: Set<String>) async -> BatchResult {
        guard !isBatchWorking, let repository else { return BatchResult() }
        isBatchWorking = true
        await acquireWork()
        defer { releaseWork(); isBatchWorking = false }
        var result = BatchResult()
        for id in ids.sorted() {
            guard let item = (items + trashedItems).first(where: { $0.id == id }) else {
                result.errors.append(L("batch.missing")); continue
            }
            do {
                switch action {
                case .category(let categoryID): try await repository.assignCategory(itemID: id, categoryID: categoryID)
                case .trash: try await repository.trash(itemID: id)
                case .restore: try await repository.restore(itemID: id)
                case .favorite(let value): if item.favorite != value { try await repository.toggleFavorite(id: id) }
                }
                result.succeeded.insert(id)
            } catch { result.errors.append(item.title + ": " + error.localizedDescription) }
        }
        await finishBatch(result)
        return result
    }
    func completeBatch(_ drafts: [BatchPrintDraft], note: String, moveFiles: Bool) async -> BatchResult {
        guard !isBatchWorking, let repository else { return BatchResult() }
        isBatchWorking = true
        await acquireWork()
        defer { releaseWork(); isBatchWorking = false }
        var result = BatchResult()
        for draft in drafts {
            do {
                guard draft.details.valid else { throw ShelfError.message(L("record.invalid")) }
                guard items.contains(where: { $0.id == draft.id }) else { throw LibraryError.itemNotFound }
                let d = draft.details
                if moveFiles {
                    _ = try await repository.completePrint(itemID: draft.id, note: note,
                        durationSeconds: d.seconds, durationSource: d.durationSource, filaments: d.records)
                } else {
                    try await repository.appendRun(itemID: draft.id, run: PrintRun(status: "completed", source: "manual", note: note,
                        durationSeconds: d.seconds, durationSource: d.durationSource, filaments: d.records))
                }
                result.succeeded.insert(draft.id)
            } catch { result.errors.append(draft.item.title + ": " + error.localizedDescription) }
        }
        await finishBatch(result)
        return result
    }
    private func finishBatch(_ result: BatchResult) async {
        selectedIDs.subtract(result.succeeded)
        await reload()
        statusMessage = String(format: L("batch.result"), result.succeeded.count, result.errors.count)
        if !result.errors.isEmpty { errorMessage = result.errors.joined(separator: "\n") }
    }
}

struct LibrarySelectionBar: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var showPrint: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            HStack {
                Text(String(format: L("batch.selected"), model.selectedItems.count)).font(Design.value).monospacedDigit()
                Spacer()
                Button(model.selectedItems.count == model.visibleItems.count ? L("batch.deselect") : L("batch.selectAll")) {
                    if model.selectedItems.count == model.visibleItems.count { model.selectedIDs = [] } else { model.selectAllVisible() }
                }.buttonStyle(.link)
            }
            HStack {
                if model.filter == .trash {
                    Button { run(.restore) } label: { Label(L("batch.restore"), systemImage: "arrow.uturn.backward") }
                } else {
                    Menu {
                        Button(L("batch.uncategorized")) { run(.category(nil)) }
                        ForEach(model.categories) { category in Button(category.name) { run(.category(category.id)) } }
                    } label: { Label(L("batch.move"), systemImage: "folder") }
                    Button { showPrint = true } label: { Label(L("batch.complete"), systemImage: "checkmark.circle") }
                    Menu {
                        Button(L("favorite.add")) { run(.favorite(true)) }
                        Button(L("favorite.remove")) { run(.favorite(false)) }
                    } label: { Image(systemName: "star") }.help(L("filter.favorites"))
                    Spacer(minLength: 0)
                    Button(role: .destructive) { run(.trash) } label: { Label(L("batch.delete"), systemImage: "trash") }
                }
            }.disabled(model.selectedItems.isEmpty)
        }.padding(Design.medium).background(Design.selection, in: RoundedRectangle(cornerRadius: Design.controlRadius))
            .disabled(model.isWorking)
    }
    private func run(_ action: LibraryBatchAction) {
        let ids = Set(model.selectedItems.map(\.id))
        Task { _ = await model.applyBatch(action, ids: ids) }
    }
}

struct BatchPrintSheet: View {
    @ObservedObject var model: LibraryViewModel
    let items: [ShelfItem]
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [BatchPrintDraft] = []
    @State private var note = ""
    @State private var moveFiles = true
    @State private var saving = false
    @State private var errors: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            Text(String(format: L("batch.printTitle"), drafts.count)).font(Design.detailTitle)
            Text(L("batch.printHint")).font(Design.caption).foregroundStyle(Design.secondary)
            VStack(alignment: .leading, spacing: Design.small) {
                TextField(L("batch.commonNote"), text: $note, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                Toggle(L("batch.movePrinted"), isOn: $moveFiles)
                if moveFiles {
                    Text(L("batch.moveHint")).font(Design.caption).foregroundStyle(Design.secondary)
                    Text(model.printDestination(for: nil).path).font(Design.caption).foregroundStyle(Design.secondary).lineLimit(1).truncationMode(.middle)
                }
            }.disabled(saving)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.regular) {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: Design.medium) {
                            HStack {
                                ModelImage(url: model.imageURL(draft.item)).frame(width: 48, height: 48)
                                Text(draft.item.title).font(Design.value)
                            }
                            PrintDetailsFields(draft: $draft.details)
                        }.padding(Design.medium).background(Design.canvas, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                    }
                    if !errors.isEmpty { Text(errors.joined(separator: "\n")).font(Design.caption).foregroundStyle(Design.warning) }
                }
            }.disabled(saving)
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(L("batch.savePrints")) { save() }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(Color.white).keyboardShortcut(.defaultAction)
                    .disabled(saving || model.isWorking || drafts.isEmpty || !drafts.allSatisfy { $0.details.valid })
            }
        }.padding(Design.large).frame(width: 660, height: 740)
            .onAppear { drafts = items.map { BatchPrintDraft(item: $0, details: model.printDetails($0)) } }
            .interactiveDismissDisabled(saving)
    }
    private func save() {
        saving = true
        Task {
            let result = await model.completeBatch(drafts, note: note, moveFiles: moveFiles)
            drafts.removeAll { result.succeeded.contains($0.id) }
            errors = result.errors
            saving = false
            // Successful rows are removed, so retrying cannot create duplicate completion records.
            if drafts.isEmpty { dismiss() }
        }
    }
}
