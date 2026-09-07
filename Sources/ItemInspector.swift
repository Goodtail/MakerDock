import SwiftUI
import PlateShelfCore

struct ItemInspector: View {
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    @State private var zoomPlate: PlateRecord?
    @State private var tags = ""
    @State private var note = ""
    @State private var showRecord = false
    @State private var showSourceEditor = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.regular) {
                HStack {
                    Text(L("detail.title")).font(Design.heading)
                    Spacer()
                    Button { model.toggleFavorite(item) } label: { Image(systemName: item.favorite ? "star.fill" : "star") }
                        .buttonStyle(.borderless).help(item.favorite ? L("favorite.remove") : L("favorite.add"))
                    Button { model.selectionID = nil } label: { Image(systemName: "sidebar.right") }.buttonStyle(.borderless).help(L("detail.close"))
                }
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(item.title).font(Design.detailTitle).textSelection(.enabled)
                    if let designer = item.designer, !designer.isEmpty { Text(designer).font(Design.body).foregroundStyle(Design.secondary) }
                    if let profile = item.profileTitle, !profile.isEmpty { Text(profile).font(Design.caption).foregroundStyle(Design.secondary) }
                }
                VStack(alignment: .leading, spacing: Design.small) {
                    Button { model.openInStudio(item) } label: { Label(L("studio.open"), systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity).padding(.vertical, Design.tiny) }
                    .buttonStyle(.borderedProminent)
                HStack {
                    if model.isPrinted(item) { Label("출력 완료", systemImage: "checkmark.circle.fill").foregroundStyle(Design.accent).font(Design.value) }
                    Button { showRecord = true } label: {
                        Label(model.isPrinted(item) ? "출력 기록 추가" : "출력 완료로 표시", systemImage: model.isPrinted(item) ? "plus" : "checkmark.circle")
                            .frame(maxWidth: .infinity).padding(.vertical, Design.tiny)
                    }.disabled(model.isWorking)
                }
                HStack {
                    CategoryMenu(model: model, item: item)
                    Spacer()
                    Button(role: .destructive) { Task { await model.trash(item) } } label: { Label("삭제", systemImage: "trash") }
                        .disabled(model.isWorking).help("MakerDock 휴지통으로 이동 · 외부 원본 유지")
                }.padding(.top, Design.tiny)
                }
                Divider()
                sourceSection
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("예상 출력 시간").font(Design.value)
                    Spacer()
                    EstimateLabel(estimate: model.displayedEstimate(item))
                }
                printerEstimateSection
                VStack(alignment: .leading, spacing: Design.medium) {
                    HStack { Text(L("plates.title")).font(Design.heading); Spacer(); Text(String(format: L("plates.overviewCount"), item.plates.count)).font(Design.caption).foregroundStyle(Design.secondary) }
                    if item.plates.isEmpty { Text(L("plates.empty")).font(Design.caption).foregroundStyle(Design.secondary) }
                    ForEach(Array(item.plates.enumerated()), id: \.element.id) { index, plate in
                        Button { zoomPlate = plate } label: {
                            HStack(spacing: Design.medium) {
                                ModelImage(url: model.imageURL(item, plate: plate)).frame(width: Design.plateThumbnail, height: Design.plateThumbnail)
                                VStack(alignment: .leading, spacing: Design.tiny) {
                                    Text(plate.name.isEmpty ? String(format: L("plate.number"), plate.id) : plate.name).font(Design.value).lineLimit(2)
                                    EstimateLabel(estimate: model.displayedEstimate(item, plate: plate), missing: "개별 시간 미제공")
                                    if item.preferredEstimate(for: plate) != nil,
                                       let seconds = model.savedEstimate(item)?.plates.first(where: { $0.id == plate.id })?.estimatedSeconds {
                                        Text("내 프린터 · \(timeText(seconds))").font(Design.caption).foregroundStyle(Design.accent)
                                    }
                                    if let grams = plate.weightGrams { Text(weightText(grams)).font(Design.caption).foregroundStyle(Design.secondary) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(Design.caption).foregroundStyle(Design.secondary)
                            }.padding(Design.small).background(Design.sidebarSurface, in: RoundedRectangle(cornerRadius: Design.imageRadius))
                        }.buttonStyle(.plain).help(L("plate.zoom"))
                            .accessibilityLabel("\(index + 1). \(plate.name), \(timeText(model.displayedEstimate(item, plate: plate)?.seconds)), \(L("plate.zoom"))")
                    }
                }
                VStack(spacing: Design.medium) {
                    if item.preferredEstimate?.source == .makerWorld, let fileTime = item.estimatedSeconds {
                        info("3MF에 저장된 시간", value: timeText(fileTime))
                    }
                    info(L("weight.estimated"), value: weightText(item.weightGrams))
                    info(L("material"), value: item.materials.isEmpty ? "—" : item.materials.joined(separator: ", "))
                    if let printer = item.printerModel, !printer.isEmpty { info(L("printer.profile"), value: printer) }
                    info(L("file.kind"), value: item.hasGCode ? L("file.sliced") : L("file.project"))
                }
                if model.displayedEstimate(item) == nil {
                    Text(L("estimate.explanation")).font(Design.caption).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: Design.medium) {
                    Text(L("tags")).font(Design.heading)
                    TextField(L("tags.placeholder"), text: $tags).textFieldStyle(.roundedBorder)
                    Text(L("note")).font(Design.heading)
                    TextEditor(text: $note).font(Design.body).frame(minHeight: Design.hero + Design.xlarge)
                        .overlay(RoundedRectangle(cornerRadius: Design.controlRadius).stroke(Design.divider))
                    HStack { Spacer(); Button(L("save")) { Task { await model.saveMetadata(item, tags: tags, note: note) } }.disabled(tags == item.tags.joined(separator: ", ") && note == item.note) }
                }
                Divider()
                VStack(alignment: .leading, spacing: Design.medium) {
                    HStack { Text(L("history")).font(Design.heading); Spacer(); Button { showRecord = true } label: { Image(systemName: "plus") }.help(L("history.add")) }
                    if item.printRuns.isEmpty { Text(L("history.empty")).font(Design.caption).foregroundStyle(Design.secondary) }
                    ForEach(item.printRuns.sorted { $0.date > $1.date }) { run in
                        VStack(alignment: .leading, spacing: Design.tiny) {
                            HStack { Image(systemName: run.status == "completed" ? "checkmark.circle" : "clock"); Text(runTitle(run.status)).font(Design.value); Spacer() }
                            Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(Design.caption).foregroundStyle(Design.secondary)
                            Text(run.source == "manual" ? L("history.manual") : L("history.studio")).font(Design.caption).foregroundStyle(Design.secondary)
                            if !run.note.isEmpty { Text(run.note).font(Design.caption).lineLimit(3) }
                            if let path = run.movedTo {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                                    Label("이동한 파일 보기", systemImage: "folder")
                                }.buttonStyle(.link).font(Design.caption).help(path)
                            }
                        }.padding(.vertical, Design.tiny)
                    }
                    Text(L("history.distinction")).font(Design.caption).foregroundStyle(Design.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: Design.small) {
                    Button(L("finder.reveal")) { model.reveal(item) }.buttonStyle(.link)
                    Text(item.filename).font(Design.caption).foregroundStyle(Design.secondary).textSelection(.enabled)
                    if model.copyCount(item) > 1 { Text(String(format: L("source.copies"), model.copyCount(item))).font(Design.caption).foregroundStyle(Design.secondary) }
                }
            }.padding(Design.regular)
        }.background(Design.surface)
        .onAppear { tags = item.tags.joined(separator: ", "); note = item.note }
        .onDisappear {
            if tags != item.tags.joined(separator: ", ") || note != item.note { Task { await model.saveMetadata(item, tags: tags, note: note) } }
        }
        .sheet(isPresented: $showRecord) { PrintRecordSheet(model: model, item: item) }
        .sheet(isPresented: $showSourceEditor) { SourceLinkSheet(model: model, item: item) }
        .sheet(item: $zoomPlate) { plate in PlateZoomView(model: model, item: item, initialPlateID: plate.id) }
    }
    private var printerEstimateSection: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            HStack(alignment: .firstTextBaseline) {
                Label("내 프린터", systemImage: "printer").font(Design.value)
                Spacer()
                if model.calculatingItemID == item.id {
                    ProgressView().controlSize(.small)
                    Button("취소") { model.estimateTask?.cancel() }.font(Design.caption)
                } else {
                    Button(model.savedEstimate(item) == nil ? "시간 계산" : "다시 계산") { model.calculateEstimate(item) }
                        .disabled(model.calculatingItemID != nil || item.plates.isEmpty).font(Design.caption)
                }
            }
            if let configuration = model.estimateConfiguration {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Design.tiny) {
                        Text(configuration.machine).font(Design.caption)
                        Text(configuration.process.isEmpty ? "파일의 출력 품질 · 재료 유지" : "\(configuration.process) · 파일 재료 유지")
                            .font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    Spacer(minLength: Design.small)
                    if let record = model.savedEstimate(item) {
                        Text(timeText(record.total)).font(Design.value).foregroundStyle(Design.accent).monospacedDigit()
                            .help("\(record.calculatedAt.formatted()) · Studio \(record.studioVersion)")
                    }
                }
                HStack {
                    Text(model.calculatingItemID == item.id ? "Studio에서 계산 중…" : "출력 전에 Studio에서 최종 설정을 확인해 주세요.")
                        .font(Design.caption).foregroundStyle(Design.secondary)
                    Spacer(minLength: 0)
                    Button("설정") { model.showSettings = true }.buttonStyle(.link).font(Design.caption)
                }
            } else {
                Button("내 프린터 선택…") { model.showSettings = true }.buttonStyle(.link).font(Design.caption)
            }
        }.padding(Design.medium).background(Design.sidebarSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
    }
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            HStack { Text(L("source.title")).font(Design.heading); Spacer(); Button { showSourceEditor = true } label: { Image(systemName: "link.badge.plus") }.buttonStyle(.borderless).help(L("source.edit")) }
            if let source = item.makerWorldSource {
                HStack(spacing: Design.medium) {
                Button { model.openSource(item) } label: { Label("모델 페이지", systemImage: "arrow.up.right") }.buttonStyle(.link)
                if let profile = source.profileURL, let url = URL(string: profile) {
                    Button("출력 프로필") { model.showMakerWorld(url) }.buttonStyle(.link)
                }
                }
                if let title = source.profileTitle, !title.isEmpty { Text(title).font(Design.caption).foregroundStyle(Design.secondary).lineLimit(2) }
                if source.estimatedSeconds != nil || source.plates?.isEmpty == false {
                    DisclosureGroup("보관한 웹 정보") {
                        VStack(alignment: .leading, spacing: Design.small) {
                            if let count = source.plateCount { Text("출력 프로필 · \(count) 플레이트") }
                            if let plates = source.plates {
                                ForEach(plates) { p in
                                    HStack { Text(p.name ?? String(format: L("plate.number"), p.id)); Spacer(); Text(timeText(p.estimatedSeconds)) }
                                    if let kind = p.plateType, !kind.isEmpty { Text(kind) }
                                }
                            }
                            Text(String(format: L("source.savedAt"), source.capturedAt.formatted(date: .abbreviated, time: .shortened)))
                            Text(L("source.webExplanation"))
                        }.padding(.top, Design.small)
                    }.font(Design.caption).foregroundStyle(Design.secondary)
                }
            } else {
                Text(L("source.missing")).font(Design.caption).foregroundStyle(Design.secondary)
                Button(L("source.edit")) { showSourceEditor = true }.buttonStyle(.link)
            }
        }
    }
    private func info(_ label: String, value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(Design.secondary); Spacer(); Text(value).font(Design.value).multilineTextAlignment(.trailing) }
    }
}
func runTitle(_ status: String) -> String {
    switch status {
    case "completed": return L("run.completed")
    case "failed": return L("run.failed")
    case "submitted": return L("run.submitted")
    case "prepared": return L("run.prepared")
    case "submission_failed": return L("run.submissionFailed")
    case "canceled": return L("run.canceled")
    case "interrupted": return L("run.interrupted")
    default: return L("run.record")
    }
}
struct PrintRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    @State private var status = "completed"
    @State private var note = ""
    @State private var isSaving = false
    @State private var moveFiles = true
    @State private var sourcePath = ""
    @State private var directory: URL?
    private var sources: [URL] { model.printSources(item) }
    private var source: URL? { sourcePath.isEmpty ? nil : URL(fileURLWithPath: sourcePath) }
    var body: some View {
        VStack(alignment: .leading, spacing: Design.large) {
            Text("출력 결과 기록").font(Design.detailTitle)
            Text(item.title).foregroundStyle(Design.secondary).lineLimit(2)
            Picker(L("history.result"), selection: $status) { Text(L("run.completed")).tag("completed"); Text(L("run.failed")).tag("failed") }.pickerStyle(.segmented)
            Text("출력 메모").font(Design.value)
            TextEditor(text: $note).font(Design.body).frame(height: 76)
                .overlay(RoundedRectangle(cornerRadius: Design.controlRadius).stroke(Design.divider))
                .accessibilityLabel("출력 메모")
            if status == "completed" {
                Toggle("완료 폴더로 파일 이동", isOn: $moveFiles)
                if moveFiles {
                    VStack(alignment: .leading, spacing: Design.small) {
                        if !sources.isEmpty {
                            Picker("이동할 파일", selection: $sourcePath) {
                                Text("앱 보관 파일만 이동").tag("")
                                ForEach(sources, id: \.path) { source in Text(source.path).tag(source.path) }
                            }.onChange(of: sourcePath) { _ in directory = model.printDestination(for: source) }
                            if sources.count > 1 { Text("선택한 원본 1개를 이동합니다. 다른 위치의 복제본은 유지됩니다.").font(Design.caption).foregroundStyle(Design.secondary) }
                        }
                        HStack {
                            Label("이동 위치", systemImage: "folder").font(Design.value)
                            Spacer()
                            if source != nil {
                                Button("폴더 변경…") { if let chosen = model.selectCompletedFolder() { directory = chosen } }
                            }
                        }
                        Text((directory ?? model.printDestination(for: source)).path).font(Design.caption).foregroundStyle(Design.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(source == nil ? "보관된 3MF를 앱의 출력 완료 폴더로 옮깁니다." : "원본과 앱 보관 파일을 정리합니다. 같은 이름이 있으면 번호를 붙여 보존합니다.")
                            .font(Design.caption).foregroundStyle(Design.secondary)
                    }.padding(Design.medium).background(Design.canvas, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                }
            }
            Text(L("history.manualExplanation")).font(Design.caption).foregroundStyle(Design.secondary)
            if let error = model.errorMessage { Text(error).font(Design.caption).foregroundStyle(Design.warning) }
            HStack {
                if isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button(status == "completed" && moveFiles ? "완료 표시하고 이동" : "기록 저장") {
                    isSaving = true
                    Task {
                        if await model.recordPrint(item, status: status, note: note, moveFiles: moveFiles,
                                                   sourceURL: source, directoryURL: directory ?? model.printDestination(for: source)) { dismiss() }
                        isSaving = false
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(isSaving || model.isWorking)
            }
        }.padding(Design.xlarge).frame(width: 560)
            .onAppear {
                sourcePath = model.preferences.completedMoveMode == "library" ? "" : sources.first?.path ?? ""
                directory = source == nil ? model.rootURL.appendingPathComponent("Files/Printed") : model.printDestination(for: source)
            }
    }
}
