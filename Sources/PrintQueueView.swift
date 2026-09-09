import SwiftUI
import PlateShelfCore

struct PrintQueueView: View {
    @ObservedObject var model: LibraryViewModel
    @AppStorage("queue.availableMinutes") private var availableMinutes = 180
    @AppStorage("queue.changeoverMinutes") private var changeoverMinutes = 5
    @State private var startNow = true
    @State private var startDate = Date()
    @State private var recordItem: ShelfItem?
    @State private var durationItem: ShelfItem?

    private var budget: Double { Double(max(0, min(10_080, availableMinutes))) * 60 }
    private var gap: Double { Double(max(0, min(60, changeoverMinutes))) * 60 }
    private var plan: PrintQueuePlan { PrintQueuePlan(jobs: model.queueJobs, availableSeconds: budget, changeoverSeconds: gap) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let start = startNow ? context.date : startDate
            let schedule = plan
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
                    planningControls(start: start, schedule: schedule)
                    List {
                        ForEach(Array(model.queuedItems.enumerated()), id: \.element.id) { index, item in
                            if let row = schedule.rows.first(where: { $0.id == item.id }) {
                                queueRow(item, index: index, row: row, start: start)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Design.canvas)
                            }
                        }.onMove { indices, destination in
                            var ids = model.printQueue.map(\.id)
                            ids.move(fromOffsets: indices, toOffset: destination)
                            Task { await model.reorderQueue(ids) }
                        }.moveDisabled(model.isWorking)
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                    HStack {
                        Text(L("queue.manualHint")).font(Design.caption).foregroundStyle(Design.secondary)
                        Spacer()
                        if model.isWorking { ProgressView().controlSize(.small) }
                    }.padding(Design.regular)
                }
            }.background(Design.canvas)
        }
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

    private func planningControls(start: Date, schedule: PrintQueuePlan) -> some View {
        VStack(alignment: .leading, spacing: Design.regular) {
            HStack(alignment: .center, spacing: Design.large) {
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(L("queue.start")).font(Design.value)
                    Toggle(L("queue.startNow"), isOn: $startNow).toggleStyle(.checkbox)
                    if !startNow {
                        DatePicker(L("queue.start"), selection: $startDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                }
                Divider().frame(height: 42)
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
                Spacer(minLength: 0)
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
                    let ids = PrintQueuePlan.fittingOrder(jobs: model.queueJobs, availableSeconds: budget, changeoverSeconds: gap)
                    Task { await model.reorderQueue(ids) }
                }.disabled(model.isWorking || PrintQueuePlan.fittingOrder(jobs: model.queueJobs, availableSeconds: budget, changeoverSeconds: gap) == model.printQueue.map(\.id))
                    .help(L("queue.fitHint"))
            }
        }.padding(Design.regular)
            .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).stroke(Design.divider))
            .padding(.horizontal, Design.large).padding(.bottom, Design.regular)
    }

    private func queueRow(_ item: ShelfItem, index: Int, row: PrintQueuePlan.Row, start: Date) -> some View {
        HStack(alignment: .center, spacing: Design.medium) {
            Text(String(index + 1)).font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.secondary).frame(width: 28)
            ModelImage(url: model.imageURL(item)).frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: Design.small) {
                Button(item.title) { model.showLibraryItem(item.id) }.font(Design.heading).lineLimit(2).buttonStyle(.plain)
                    .help(L("queue.viewModel"))
                HStack(spacing: Design.small) {
                    Button { durationItem = item } label: {
                        Label(row.seconds.map { timeText($0) } ?? L("queue.setTime"), systemImage: "clock")
                    }.buttonStyle(.link).font(Design.value).disabled(model.isWorking)
                    Text(model.printQueue.first { $0.id == item.id }?.durationSeconds != nil ? L("queue.manualTime") : model.displayedEstimate(item)?.sourceLabel ?? "")
                        .font(Design.caption).foregroundStyle(Design.secondary)
                    Text(String(format: L("queue.plates"), item.plates.count)).font(Design.caption).foregroundStyle(Design.secondary)
                }
                if let from = row.startOffset, let until = row.endOffset {
                    Text(String(format: L("queue.slot"), dateText(start.addingTimeInterval(from)), dateText(start.addingTimeInterval(until))))
                        .font(Design.caption).foregroundStyle(Design.secondary).lineLimit(2)
                } else { Text(L("queue.scheduleUnknown")).font(Design.caption).foregroundStyle(Design.secondary) }
                Label(L(row.fits ? "queue.within" : row.seconds == nil || row.endOffset == nil ? "queue.needsTime" : "queue.over"), systemImage: row.fits ? "checkmark.circle" : "clock")
                    .font(Design.caption).foregroundStyle(row.fits ? Design.accent : Design.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Design.medium) {
                HStack(spacing: Design.medium) {
                    Button { Task { await model.moveQueueItem(item.id, by: -1) } } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).help(L("queue.up")).accessibilityLabel(L("queue.up"))
                    Button { Task { await model.moveQueueItem(item.id, by: 1) } } label: { Image(systemName: "arrow.down") }
                        .disabled(index == model.printQueue.count - 1).help(L("queue.down")).accessibilityLabel(L("queue.down"))
                    Button { Task { await model.removeQueueItem(item.id) } } label: { Image(systemName: "minus.circle") }
                        .help(L("queue.remove")).accessibilityLabel(L("queue.remove"))
                }.buttonStyle(.borderless).foregroundStyle(Design.secondary)
                HStack {
                    Button(L("queue.openStudio")) { model.openInStudio(item) }
                    Button { recordItem = item } label: { Label(L("queue.complete"), systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white)
                }
            }.disabled(model.isWorking)
        }.padding(Design.regular)
            .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).stroke(row.fits ? Design.accent.opacity(0.32) : Design.divider))
            .padding(.vertical, Design.tiny)
            .accessibilityElement(children: .contain)
            .contextMenu {
                Button(L("queue.viewModel")) { model.showLibraryItem(item.id) }
                Button(L("queue.setTime")) { durationItem = item }
                Button(L("queue.remove")) { Task { await model.removeQueueItem(item.id) } }
            }
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
