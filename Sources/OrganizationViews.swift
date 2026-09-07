import SwiftUI
import PlateShelfCore

struct CategoryEditRequest: Identifiable {
    let id = UUID()
    var categoryID: String?
    var itemID: String?
    var initialName: String
    init(category: LibraryCategory? = nil, itemID: String? = nil) {
        self.categoryID = category?.id; self.itemID = itemID; self.initialName = category?.name ?? ""
    }
}

struct CategoryMenu: View {
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    var body: some View {
        Menu {
            Button { Task { await model.assignCategory(item, categoryID: nil) } } label: {
                Label("미분류", systemImage: item.categoryID == nil ? "checkmark" : "tray")
            }
            ForEach(model.categories) { category in
                Button { Task { await model.assignCategory(item, categoryID: category.id) } } label: {
                    Label(category.name, systemImage: item.categoryID == category.id ? "checkmark" : "folder")
                }
            }
            Divider()
            Button("새 분류 만들기…") { model.categoryEditor = CategoryEditRequest(itemID: item.id) }
        } label: {
            Label(model.categoryName(item), systemImage: "folder")
        }.disabled(model.isWorking).help("분류 선택")
    }
}

struct CategoryEditorSheet: View {
    @ObservedObject var model: LibraryViewModel
    let request: CategoryEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Design.large) {
            Label(request.categoryID == nil ? "새 분류" : "분류 이름 변경", systemImage: "folder.badge.plus").font(Design.detailTitle)
            TextField("예: 생활용품, 작업 도구, 선물", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                .onSubmit { save() }
            Text(request.itemID == nil ? "분류를 만들어 모델을 모아보세요. 분류 이름을 바꿔도 파일 위치는 유지됩니다." : "새 분류를 만들고 선택한 모델에 바로 적용합니다.")
                .font(Design.caption).foregroundStyle(Design.secondary)
            if let error { Text(error).font(Design.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("저장") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(Design.xlarge).frame(width: 420)
            .onAppear { name = request.initialName; nameFocused = true }
    }
    private func save() {
        guard !isSaving, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        Task {
            do { try await model.saveCategory(request, name: name); dismiss() }
            catch { self.error = error.localizedDescription }
            isSaving = false
        }
    }
}

struct TrashInspector: View {
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.large) {
                Label("휴지통", systemImage: "trash").font(Design.heading)
                ModelImage(url: model.imageURL(item)).frame(height: 220)
                Text(item.title).font(Design.detailTitle).textSelection(.enabled)
                if let date = item.deletedAt { Text("삭제일: " + date.formatted(date: .abbreviated, time: .shortened)).font(Design.caption).foregroundStyle(Design.secondary) }
                Button { Task { await model.restore(item.id) } } label: { Label("모델 복원", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(model.isWorking)
                Text("분류·메모·출력 기록을 함께 복원합니다. 외부 원본 파일은 삭제하지 않았습니다.").font(Design.body).foregroundStyle(Design.secondary)
                Divider()
                Label(model.categoryName(item), systemImage: "folder")
                if !item.note.isEmpty { Text(item.note).textSelection(.enabled) }
                Text("출력 기록 \(item.printRuns.count)개").font(Design.caption)
                Button("보관 파일을 Finder에서 보기") { model.reveal(item) }.buttonStyle(.link)
            }.padding(Design.large)
        }.background(Design.surface)
    }
}
