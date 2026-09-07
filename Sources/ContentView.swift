import SwiftUI
import PlateShelfCore
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: LibraryViewModel
    @StateObject private var browser = MakerWorldBrowser()
    @State private var recordItem: ShelfItem?
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var sidebarFocused: Bool
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: Design.sidebar, ideal: Design.sidebar)
        } detail: {
            if model.filter == .makerWorld {
                MakerWorldView(model: model, browser: browser)
            } else {
                HSplitView {
                    library.frame(minWidth: Design.cardMin * 2)
                    if let item = model.selected {
                        Group {
                            if item.isTrashed { TrashInspector(model: model, item: item) }
                            else { ItemInspector(model: model, item: item).id(item.id) }
                        }.frame(minWidth: Design.inspector, idealWidth: Design.inspector, maxWidth: Design.inspector + Design.hero)
                    }
                }
            }
        }
        .font(Design.body).foregroundStyle(Design.ink)
        .toolbarBackground(Design.surface, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup {
                if model.filter != .makerWorld {
                    Button { model.chooseFolder() } label: { Label(L("import.folder"), systemImage: "folder.badge.plus") }.disabled(model.isWorking)
                    Button { model.chooseFiles() } label: { Label(L("import.files"), systemImage: "plus") }.disabled(model.isWorking)
                    if let item = model.selected {
                        if item.isTrashed {
                            Button { Task { await model.restore(item.id) } } label: { Label("복원", systemImage: "arrow.uturn.backward") }.disabled(model.isWorking)
                        } else {
                            CategoryMenu(model: model, item: item)
                            Button(role: .destructive) { Task { await model.trash(item) } } label: { Label("휴지통으로 이동", systemImage: "trash") }.disabled(model.isWorking)
                        }
                    }
                    Button { Task { await model.refresh() } } label: { Label(L("refresh"), systemImage: "arrow.clockwise") }.disabled(model.isWorking)
                }
                Button { model.showSettings = true } label: { Label(L("settings"), systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(item: $model.categoryEditor) { request in CategoryEditorSheet(model: model, request: request) }
        .onChange(of: model.filter) { _ in model.syncSelection() }
        .sheet(item: $recordItem) { item in PrintRecordSheet(model: model, item: item) }
        .onChange(of: model.browserRequest) { request in
            if let request { browser.start(model: model, location: request) }
        }
        .onChange(of: model.browserReloadRequest) { _ in browser.reload() }
        .alert(L("error.title"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("ok"), role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }
                    if let url { urls.append(url) }
                }
                await model.importFiles(urls)
            }
            return true
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.small) {
                Image(AppIdentity.logo).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Design.tiny) {
                    Text(AppIdentity.name).font(Design.heading)
                    Text(L("sidebar.subtitle")).font(Design.caption).foregroundStyle(Design.secondary)
                }
            }.padding(Design.large)
            List(selection: Binding<ShelfFilter?>(get: { model.filter }, set: { if let value = $0 { model.filter = value } })) {
                Section("탐색") {
                    sideRow(.makerWorld, icon: "globe")
                }
                Section(L("sidebar.library")) {
                    sideRow(.all, icon: "square.grid.2x2", count: model.items.count)
                    sideRow(.favorites, icon: "star", count: model.items.filter(\.favorite).count)
                    sideRow(.printed, icon: "checkmark.circle", count: model.printedCount)
                    sideRow(.unprinted, icon: "tray", count: model.items.count - model.printedCount)
                    sideRow(.duplicates, icon: "square.on.square", count: model.items.filter { model.copyCount($0) > 1 }.count)
                }
                Section {
                    sideRow(.uncategorized, icon: "tray", count: model.items.filter { $0.categoryID == nil }.count)
                    ForEach(model.categories) { category in
                        sideRow(.category(category.id), icon: "folder", count: model.items.filter { $0.categoryID == category.id }.count, title: category.name)
                            .contextMenu {
                                Button("이름 변경…") { model.categoryEditor = CategoryEditRequest(category: category) }
                                Button("분류 삭제 · 모델 유지", role: .destructive) { Task { await model.deleteCategory(category) } }
                            }
                    }
                    Button { model.categoryEditor = CategoryEditRequest() } label: { Label("새 분류", systemImage: "folder.badge.plus") }
                        .buttonStyle(.plain).foregroundStyle(Design.accent)
                } header: { Text("분류") }
                Section { sideRow(.trash, icon: "trash", count: model.trashedItems.count) }
                Section(L("tags")) {
                    if model.allTags.isEmpty { Text(L("tags.empty")).font(Design.caption).foregroundStyle(Design.secondary) }
                    ForEach(model.allTags, id: \.self) { tag in sideRow(.tag(tag), icon: "tag", count: model.items.filter { $0.tags.contains(tag) }.count) }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden).focused($sidebarFocused)
            VStack(alignment: .leading, spacing: Design.small) {
                Label(L("local.storage"), systemImage: "internaldrive").font(Design.value)
                Text(String(format: L("folder.count"), model.preferences.folders.count)).font(Design.caption).foregroundStyle(Design.secondary)
                Button(L("manage.folders")) { model.showSettings = true }.buttonStyle(.link).font(Design.caption)
            }.padding(Design.large)
        }.background(Design.sidebarSurface)
    }
    private func sideRow(_ filter: ShelfFilter, icon: String, count: Int? = nil, title: String? = nil) -> some View {
        // Match the native blue selection; keep the inactive gray selection readable.
        let highlighted = model.filter == filter && sidebarFocused && controlActiveState != .inactive
        return HStack {
            Label(title ?? filter.title, systemImage: icon)
                .foregroundStyle(highlighted ? Color.white : Design.ink)
            Spacer()
            if let count {
                Text("\(count)").foregroundStyle(highlighted ? Color.white : Design.secondary)
                    .monospacedDigit().font(Design.caption)
            }
        }.tag(filter).padding(.vertical, Design.tiny)
    }
    private var library: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Design.regular) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Design.small) {
                        Text(model.filterTitle).font(Design.title)
                        Text(String(format: L("library.count"), model.visibleItems.count)).font(Design.body).foregroundStyle(Design.secondary)
                    }
                    Spacer()
                    Menu {
                        Picker(L("sort"), selection: $model.sort) {
                            ForEach(ShelfSort.allCases, id: \.self) { order in Text(order.title).tag(order) }
                        }
                    } label: { Label(model.sort.title, systemImage: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize()
                    Picker(L("view.mode"), selection: $model.listMode) {
                        Image(systemName: "square.grid.2x2").tag(false)
                        Image(systemName: "list.bullet").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: Design.hero + Design.large)
                }
                if model.filter == .trash {
                    Text("MakerDock 보관 파일을 휴지통에 보관합니다. 복원하면 분류·메모·출력 기록도 돌아옵니다. 외부 원본은 유지됩니다.")
                        .font(Design.caption).foregroundStyle(Design.secondary)
                }
                HStack(spacing: Design.small) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Design.secondary)
                    TextField(L("search.placeholder"), text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(Design.medium).background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Design.controlRadius).stroke(Design.divider))
            }.padding(Design.large)
            if model.visibleItems.isEmpty {
                Spacer()
                VStack(spacing: Design.regular) {
                    Image(systemName: model.filter == .trash ? "trash" : model.items.isEmpty ? "shippingbox" : "magnifyingglass").font(.system(size: Design.jumbo)).foregroundStyle(Design.secondary)
                    Text(model.filter == .trash && model.search.isEmpty ? "휴지통이 비어 있습니다" : model.items.isEmpty ? L("empty.title") : L("search.empty")).font(Design.heading)
                    Text(model.filter == .trash && model.search.isEmpty ? "삭제한 모델을 여기에서 복원할 수 있습니다." : model.items.isEmpty ? L("empty.description") : L("search.retry")).multilineTextAlignment(.center).foregroundStyle(Design.secondary)
                    if model.items.isEmpty && model.filter != .trash { Button(L("import.folder")) { model.chooseFolder() }.buttonStyle(.borderedProminent).disabled(model.isWorking) }
                    else { Button(L("filter.reset")) { model.search = ""; model.filter = .all } }
                }.padding(Design.xlarge)
                Spacer()
            } else {
                ScrollView {
                    if model.listMode {
                        LazyVStack(spacing: Design.small) { ForEach(model.visibleItems) { item in modelRow(item) } }.padding(.horizontal, Design.large)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Design.cardMin, maximum: Design.cardMax), spacing: Design.regular)], spacing: Design.regular) {
                            ForEach(model.visibleItems) { item in
                                ModelCard(item: item, imageURL: model.imageURL(item), selected: model.selectionID == item.id, printed: model.isPrinted(item), estimate: model.displayedEstimate(item)) { model.selectionID = item.id }
                                    .contextMenu { itemMenu(item) }
                            }
                        }.padding(.horizontal, Design.large).padding(.bottom, Design.large)
                    }
                }
            }
            Divider()
            HStack(spacing: Design.small) {
                if model.isWorking { ProgressView().controlSize(.small) }
                else { Image(systemName: "checkmark.circle").foregroundStyle(Design.accent) }
                Text(model.statusMessage.isEmpty ? L("status.ready") : model.statusMessage).lineLimit(1)
                if let id = model.lastTrashedID {
                    Button("삭제 취소") { Task { await model.restore(id) } }.buttonStyle(.link).disabled(model.isWorking)
                }
                Spacer()
                if model.duplicateCount > 0 { Text(String(format: L("duplicates.merged"), model.duplicateCount)).lineLimit(1) }
            }.font(Design.caption).foregroundStyle(Design.secondary).padding(Design.medium)
        }.background(Design.canvas)
    }
    private func modelRow(_ item: ShelfItem) -> some View {
        Button { model.selectionID = item.id } label: {
            HStack(spacing: Design.regular) {
                ModelImage(url: model.imageURL(item)).frame(width: Design.hero, height: Design.hero)
                VStack(alignment: .leading, spacing: Design.tiny) {
                    Text(item.title).font(Design.value).lineLimit(1)
                    Text(item.profileTitle ?? item.filename).font(Design.caption).foregroundStyle(Design.secondary).lineLimit(1)
                }
                Spacer()
                EstimateLabel(estimate: model.displayedEstimate(item))
                if model.isPrinted(item) { Label("출력 완료", systemImage: "checkmark.circle.fill").foregroundStyle(Design.accent).font(Design.caption) }
                if item.favorite { Image(systemName: "star.fill").foregroundStyle(Design.accent) }
            }.padding(Design.medium).background(model.selectionID == item.id ? Design.selection : Design.surface, in: RoundedRectangle(cornerRadius: Design.imageRadius))
        }.buttonStyle(.plain).contextMenu { itemMenu(item) }
    }
    @ViewBuilder private func itemMenu(_ item: ShelfItem) -> some View {
        if item.isTrashed {
            Button("복원") { Task { await model.restore(item.id) } }.disabled(model.isWorking)
            Button(L("finder.reveal")) { model.reveal(item) }
        } else {
        CategoryMenu(model: model, item: item)
        Divider()
        Button(L("studio.open")) { model.openInStudio(item) }
        Button(model.isPrinted(item) ? "출력 기록 추가…" : "출력 완료로 표시…") { recordItem = item }.disabled(model.isWorking)
        Button(item.favorite ? L("favorite.remove") : L("favorite.add")) { model.toggleFavorite(item) }
        Button(L("finder.reveal")) { model.reveal(item) }
        Divider()
        Button("휴지통으로 이동", role: .destructive) { Task { await model.trash(item) } }.disabled(model.isWorking)
        }
    }
}

struct ModelImage: View {
    let url: URL?
    var body: some View {
        ZStack {
            Design.preview
            if let url, let image = ThumbnailCache.shared.image(at: url) {
                Image(nsImage: image).resizable().scaledToFit().padding(Design.small)
            } else {
                Image(systemName: "cube.transparent").font(.system(size: Design.xlarge)).foregroundStyle(Design.secondary)
            }
        }.clipShape(RoundedRectangle(cornerRadius: Design.imageRadius))
    }
}
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(at url: URL) -> NSImage? {
        if let image = cache.object(forKey: url.path as NSString) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url.path as NSString); return image
    }
}
struct ModelCard: View {
    let item: ShelfItem
    let imageURL: URL?
    let selected: Bool
    let printed: Bool
    let estimate: PrintEstimate?
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ModelImage(url: imageURL).frame(height: Design.imageHeight)
                    .overlay(alignment: .topTrailing) {
                        if item.favorite { Image(systemName: "star.fill").foregroundStyle(Design.accent).padding(Design.small).background(Design.surface, in: Circle()).padding(Design.small) }
                    }
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(item.title).font(Design.value).lineLimit(2).frame(height: Design.xlarge, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Design.tiny) {
                        Text(item.materials.first ?? L("material.unknown"))
                        Text("·")
                        Text(String(format: L("plates.count"), item.plates.count))
                        Spacer(minLength: 0)
                        if printed { Label("출력 완료", systemImage: "checkmark.circle.fill").foregroundStyle(Design.accent).fixedSize() }
                    }.font(Design.caption).foregroundStyle(Design.secondary)
                    EstimateLabel(estimate: estimate)
                }.padding(Design.medium)
            }
            .background(selected || hover ? Design.selection : Design.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).strokeBorder(selected ? Design.accent : Design.divider, lineWidth: selected ? 2 : 1))
            .shadow(color: Design.ink.opacity(selected ? 0.07 : 0.025), radius: selected ? 8 : 3, y: 2)
        }.buttonStyle(.plain).onHover { hover = $0 }.help(item.title)
    }
}
