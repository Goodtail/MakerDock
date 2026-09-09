import SwiftUI
import PlateShelfCore
import UniformTypeIdentifiers

struct PrintQueueView: View {
    @ObservedObject var model: LibraryViewModel
    @AppStorage("queue.availableMinutes") private var availableMinutes = 180
    @AppStorage("queue.changeoverMinutes") private var changeoverMinutes = 5
    @State private var startNow = true
    @State private var startDate = Date()
    @State private var recordItem: ShelfItem?
    @State private var durationItem: ShelfItem?
    @State private var startingItem: ShelfItem?
    @State private var draggedItemID: String?
    @State private var contentWidth: CGFloat = 1000

    private var budget: Double { Double(max(0, min(10_080, availableMinutes))) * 60 }
    private var gap: Double { Double(max(0, min(60, changeoverMinutes))) * 60 }


    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let start = startNow || model.activePrint != nil ? context.date : startDate
            let schedule = PrintQueuePlan(jobs: model.queueJobs(at: context.date), availableSeconds: budget, changeoverSeconds: gap)
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.printQueue.isEmpty {
                    Spacer()
                    VStack(spacing: Design.regular) {
                        Image(systemName: "list.number").font(.system(size: 40)).foregroundStyle(Design.accent)
                        Text(L("queue.empty")).font(Design.detailTitle)
                        Text(L("queue.emptyHint")).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
                        Button(L("queue.browse")) { model.filter = .all }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white)
                    }.frame(maxWidth: .infinity).padding(Design.large)
                    Spacer()
                } else {
                    planningControls(start: start, now: context.date, schedule: schedule)
                    ScrollView {
                        LazyVStack(spacing: Design.medium) {
                            ForEach(Array(model.queuedItems.enumerated()), id: \.element.id) { index, item in
                                if let row = schedule.rows.first(where: { $0.id == item.id }) {
                                    queueRow(item, index: index, row: row, start: start, now: context.date)
                                        .onDrag {
                                            guard !model.isWorking, model.queueEntry(item)?.isPrinting != true else { return NSItemProvider() }
                                            draggedItemID = item.id
                                            return NSItemProvider(object: item.id as NSString)
                                        }
                                        .onDrop(of: [UTType.plainText], delegate: QueueReorderDrop(model: model, targetID: item.id, draggedID: $draggedItemID))
                                }
                            }
                        }.padding(.horizontal, Design.large).padding(.bottom, Design.regular)
                    }

                    HStack {
                        Text(L("queue.manualHint")).font(Design.caption).foregroundStyle(Design.secondary)
                        Spacer()
                        if model.isWorking { ProgressView().controlSize(.small) }
                    }.padding(.horizontal, Design.large).padding(.vertical, Design.regular)
                }
            }.background(Design.canvas)
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { contentWidth = proxy.size.width }.onChange(of: proxy.size.width) { contentWidth = $0 }
        })
        .sheet(item: $startingItem) { item in QueueStartSheet(model: model, item: item) }
        .sheet(item: $recordItem) { item in PrintRecordSheet(model: model, item: item) }
        .sheet(item: $durationItem) { item in QueueDurationSheet(model: model, item: item) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.small) {
                Text(L("queue.title")).font(Design.title)
                Text(String(format: L("queue.count"), model.printQueue.count)).foregroundStyle(Design.secondary)
            }
            Spacer()
            Button { model.filter = .all } label: { Label(L("queue.chooseModels"), systemImage: "plus") }
        }.padding(Design.large)
    }

    private func planningControls(start: Date, now: Date, schedule: PrintQueuePlan) -> some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            let controls = contentWidth < 720 ? AnyLayout(VStackLayout(alignment: .leading, spacing: Design.medium)) : AnyLayout(HStackLayout(alignment: .center, spacing: Design.large))
            controls {
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(L("queue.start")).font(Design.value)
                    if model.activePrint != nil { Text(L("queue.printingNow")).foregroundStyle(Design.accent) }
                    else { Toggle(L("queue.startNow"), isOn: $startNow).toggleStyle(.checkbox) }
                    if !startNow && model.activePrint == nil {
                        DatePicker(L("queue.start"), selection: $startDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                }
                if contentWidth >= 720 { Divider().frame(height: 42) }
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(L("queue.available")).font(Design.value)
                    HStack(spacing: Design.small) {
                        TextField("3", value: Binding(get: { max(0, availableMinutes) / 60 }, set: { availableMinutes = min(168, max(0, $0)) * 60 + max(0, availableMinutes) % 60 }), format: .number.grouping(.never))
                            .frame(width: 48).accessibilityLabel(L("queue.availableHours"))
                        Text(L("record.hours"))
                        TextField("0", value: Binding(get: { max(0, availableMinutes) % 60 }, set: { availableMinutes = max(0, availableMinutes) / 60 * 60 + min(59, max(0, $0)) }), format: .number.grouping(.never))
                            .frame(width: 44).accessibilityLabel(L("queue.availableMinutes"))
                        Text(L("record.minutes"))
                    }.textFieldStyle(.roundedBorder)
                }
                if contentWidth >= 720 { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(L("queue.changeover")).font(Design.value)
                    Stepper(value: $changeoverMinutes, in: 0...60) {
                        Text(String(format: L("time.minutes"), changeoverMinutes)).monospacedDigit().frame(minWidth: 56, alignment: .leading)
                    }
                }
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(String(format: L("queue.fits"), schedule.fitsCount, model.printQueue.count)).font(Design.heading)
                    Text(String(format: L("queue.until"), dateText(start.addingTimeInterval(budget)))).font(Design.caption).foregroundStyle(Design.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Design.small) {
                    Text(String(format: L("queue.remaining"), durationText(schedule.remainingSeconds))).font(Design.value).monospacedDigit()
                    Text(String(format: L(schedule.totalSeconds == nil ? "queue.knownTotal" : "queue.total"), durationText(schedule.totalSeconds ?? schedule.knownSeconds)))
                        .font(Design.caption).foregroundStyle(Design.secondary)
                }
            }
            HStack {
                if schedule.unknownCount > 0 {
                    Label(String(format: L("queue.unknown"), schedule.unknownCount), systemImage: "clock.badge.questionmark")
                        .font(Design.caption).foregroundStyle(Design.warning)
                } else { Text(L("queue.reorderHint")).font(Design.caption).foregroundStyle(Design.secondary) }
                Spacer()
                Button(L("queue.fitOrder")) {
                    let ids = model.fittingQueueOrder(at: now, budget: budget, gap: gap)
                    Task { await model.reorderQueue(ids) }
                }.disabled(model.isWorking || model.fittingQueueOrder(at: now, budget: budget, gap: gap) == model.printQueue.map(\.id))
                    .help(L("queue.fitHint"))
            }
        }.padding(Design.regular)
            .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).stroke(Design.divider))
            .padding(.horizontal, Design.large).padding(.bottom, Design.regular)
    }

    private func queueRow(_ item: ShelfItem, index: Int, row: PrintQueuePlan.Row, start: Date, now: Date) -> some View {
        let entry = model.queueEntry(item)
        let printing = entry?.isPrinting == true
        return VStack(alignment: .leading, spacing: Design.medium) {
            HStack(alignment: .top, spacing: Design.medium) {
                ModelImage(url: model.imageURL(item)).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: Design.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(printing ? L("queue.printing") : String(index + 1)).font(Design.caption).foregroundStyle(printing ? Design.accent : Design.secondary)
                        Button(item.title) { model.showLibraryItem(item.id) }.font(Design.heading).lineLimit(2).buttonStyle(.plain)
                    }
                    HStack(spacing: Design.small) {
                        Button { durationItem = item } label: {
                            Label(model.queueSeconds(item).map { timeText($0) } ?? L("queue.setTime"), systemImage: "clock")
                        }.buttonStyle(.link).font(Design.value).disabled(model.isWorking)
                        Text(entry?.durationSeconds != nil ? L("queue.manualTime") : model.displayedEstimate(item)?.sourceLabel ?? "")
                            .font(Design.caption).foregroundStyle(Design.secondary)
                        Text(String(format: L("queue.plates"), item.plates.count)).font(Design.caption).foregroundStyle(Design.secondary)
                    }
                    if let began = entry?.startedAt {
                        Text(String(format: L("queue.startedAt"), dateText(began))).font(Design.caption).foregroundStyle(Design.secondary)
                        if let remaining = entry?.remainingSeconds(at: now, estimate: model.displayedEstimate(item)?.seconds) {
                            Text(String(format: L("queue.printRemaining"), timeText(remaining), dateText(now.addingTimeInterval(remaining))))
                                .font(Design.value).foregroundStyle(Design.accent)
                        } else {
                            Text(L(model.queueSeconds(item) == nil ? "queue.scheduleUnknown" : "queue.overdue"))
                                .font(Design.caption).foregroundStyle(Design.warning)
                        }
                    } else if let from = row.startOffset, let until = row.endOffset {
                        Text(String(format: L("queue.slot"), dateText(start.addingTimeInterval(from)), dateText(start.addingTimeInterval(until))))
                            .font(Design.caption).foregroundStyle(Design.secondary)
                    } else { Text(L("queue.scheduleUnknown")).font(Design.caption).foregroundStyle(Design.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.calculatingItemID == item.id || model.pendingEstimateIDs.contains(item.id) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L(model.calculatingItemID == item.id ? "queue.calculating" : "queue.calculationWaiting")).font(Design.caption).foregroundStyle(Design.secondary)
                }
            } else if let error = model.estimateErrors[item.id] {
                HStack(alignment: .top) {
                    Text(error).font(Design.caption).foregroundStyle(Design.warning).lineLimit(3).help(error)
                    Spacer(minLength: Design.small)
                    Button(L("queue.retryEstimate")) { model.calculateEstimate(item) }.font(Design.caption)
                }
            } else if model.displayedEstimate(item) == nil && model.estimateConfiguration == nil {
                Button(L("queue.configureEstimate")) { model.showSettings = true }.buttonStyle(.link).font(Design.caption)
            }
            ViewThatFits(in: .horizontal) {
                HStack { queueActions(item, printing: printing); Spacer(); orderActions(item, index: index, printing: printing) }
                VStack(alignment: .leading, spacing: Design.small) {
                    queueActions(item, printing: printing)
                    orderActions(item, index: index, printing: printing)
                }
            }.disabled(model.isWorking)
        }.padding(Design.regular)
            .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).stroke(printing ? Design.accent : Design.divider))
            .accessibilityElement(children: .contain)
            .contextMenu {
                Button(L("queue.viewModel")) { model.showLibraryItem(item.id) }
                Button(L("queue.setTime")) { durationItem = item }
                if printing { Button(L("queue.backToWaiting")) { Task { await model.returnQueuePrintToWaiting(item) } } }
                else { Button(L("queue.remove")) { Task { await model.removeQueueItem(item.id) } } }
            }
    }
    private func queueActions(_ item: ShelfItem, printing: Bool) -> some View {
        HStack(spacing: Design.small) {
            Button(L("queue.openStudio")) { model.openInStudio(item) }
            if printing {
                Menu {
                    Button(L("queue.editStart")) { startingItem = item }
                    Button(L("queue.backToWaiting")) { Task { await model.returnQueuePrintToWaiting(item) } }
                } label: { Label(L("queue.printing"), systemImage: "printer.fill") }.menuStyle(.borderlessButton).fixedSize()
            } else {
                Button(L("queue.markStarted")) { startingItem = item }
                    .disabled(model.activePrint != nil).help(L("queue.startHint"))
            }
            Button { recordItem = item } label: { Label(L("queue.complete"), systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white)
        }
    }
    private func orderActions(_ item: ShelfItem, index: Int, printing: Bool) -> some View {
        HStack(spacing: Design.medium) {
            Button { Task { await model.moveQueueItem(item.id, by: -1) } } label: { Image(systemName: "arrow.up") }
                .disabled(printing || index == 0 || (model.activePrint != nil && index == 1)).help(L("queue.up")).accessibilityLabel(L("queue.up"))
            Button { Task { await model.moveQueueItem(item.id, by: 1) } } label: { Image(systemName: "arrow.down") }
                .disabled(printing || index == model.printQueue.count - 1).help(L("queue.down")).accessibilityLabel(L("queue.down"))
            Button { Task { await model.removeQueueItem(item.id) } } label: { Image(systemName: "minus.circle") }
                .disabled(printing).help(L("queue.remove")).accessibilityLabel(L("queue.remove"))
        }.buttonStyle(.borderless).foregroundStyle(Design.secondary)
    }
    private func durationText(_ seconds: Double) -> String { seconds > 0 ? timeText(seconds) : String(format: L("time.minutes"), 0) }
}

struct QueueDurationSheet: View {
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    @Environment(\.dismiss) private var dismiss
    @State private var hours = ""
    @State private var minutes = ""
    @State private var saving = false
    private var seconds: Double? {
        guard let h = Int(hours), let m = Int(minutes), h >= 0, h <= 8760, m >= 0, m < 60 else { return nil }
        return PrintQueuePlan.duration(Double(h * 3600 + m * 60))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            Text(L("queue.setTime")).font(Design.detailTitle)
            Text(item.title).foregroundStyle(Design.secondary).lineLimit(2)
            HStack {
                TextField("0", text: $hours).frame(width: 65).accessibilityLabel(L("record.hours"))
                Text(L("record.hours"))
                TextField("0", text: $minutes).frame(width: 65).accessibilityLabel(L("record.minutes"))
                Text(L("record.minutes"))
            }.textFieldStyle(.roundedBorder)
            Text(L("queue.timeHint")).font(Design.caption).foregroundStyle(Design.secondary)
            if let estimate = model.displayedEstimate(item) {
                Button(String(format: L("queue.useSaved"), timeText(estimate.seconds))) {
                    saving = true
                    Task { if await model.setQueueDuration(item.id, seconds: nil) { dismiss() }; saving = false }
                }.disabled(saving || model.isWorking)
            }
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(L("queue.save")) {
                    guard let seconds else { return }; saving = true
                    Task { if await model.setQueueDuration(item.id, seconds: seconds) { dismiss() }; saving = false }
                }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white).keyboardShortcut(.defaultAction)
                    .disabled(seconds == nil || saving || model.isWorking)
            }
        }.padding(Design.large).frame(width: 430)
            .onAppear {
                let total = Int((PrintQueuePlan.duration(model.queueSeconds(item)) ?? 0) / 60)
                hours = String(total / 60); minutes = String(total % 60)
            }.interactiveDismissDisabled(saving)
    }
}

struct QueueStartSheet: View {
    @ObservedObject var model: LibraryViewModel
    let item: ShelfItem
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            Text(L("queue.markStarted")).font(Design.detailTitle)
            Text(item.title).foregroundStyle(Design.secondary).lineLimit(3)
            DatePicker(L("queue.actualStart"), selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            Text(L("queue.startHint")).font(Design.caption).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("queue.save")) {
                    saving = true
                    Task { if await model.startQueuePrint(item, at: startedAt) { dismiss() }; saving = false }
                }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white).keyboardShortcut(.defaultAction)
            }.disabled(saving || model.isWorking)
        }.padding(Design.large).frame(width: 430)
            .onAppear { startedAt = model.queueEntry(item)?.startedAt ?? Date() }
            .interactiveDismissDisabled(saving)
    }
}

@MainActor private struct QueueReorderDrop: DropDelegate {
    let model: LibraryViewModel
    let targetID: String
    @Binding var draggedID: String?
    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedID, !model.isWorking else { return false }
        return model.printQueue.contains { $0.id == draggedID && !$0.isPrinting } &&
            model.printQueue.contains { $0.id == targetID && !$0.isPrinting }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: validateDrop(info: info) ? .move : .forbidden) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let source = draggedID else { return false }
        draggedID = nil
        var ids = model.printQueue.map(\.id)
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: targetID), from != to else { return false }
        ids.remove(at: from); ids.insert(source, at: min(to, ids.count))
        Task { await model.reorderQueue(ids) }
        return true
    }
}
