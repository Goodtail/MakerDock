import SwiftUI
import PlateShelfCore

struct PrinterConnectionSettings: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var monitor: PrinterMonitor
    @State private var host = ""
    @State private var serial = ""
    @State private var code = ""
    private var configuration: PrinterConnectionConfiguration {
        PrinterConnectionConfiguration(host: host.trimmingCharacters(in: .whitespacesAndNewlines), serial: serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), enabled: true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Design.medium) {
            Text(L("printer.setupHint")).font(Design.caption).foregroundStyle(Design.secondary)
            Grid(alignment: .leading, horizontalSpacing: Design.medium, verticalSpacing: Design.small) {
                GridRow { Text(L("printer.ip")); TextField("192.168.1.100", text: $host).accessibilityIdentifier("printer.host") }
                GridRow { Text(L("printer.serial")); TextField(L("printer.serialPlaceholder"), text: $serial).accessibilityIdentifier("printer.serial") }
                GridRow { Text(L("printer.accessCode")); SecureField(L("printer.codePlaceholder"), text: $code).accessibilityIdentifier("printer.code") }
            }.textFieldStyle(.roundedBorder)
            Text(L("printer.codeHint")).font(Design.caption).foregroundStyle(Design.secondary)
            HStack {
                Button(L("printer.saveConnect")) {
                    monitor.saveAndConnect(configuration, code: code, studioPath: model.preferences.studioPath)
                    code = ""
                }.disabled(!configuration.valid).accessibilityIdentifier("printer.connect")
                if monitor.configuration.enabled { Button(L("printer.disconnect")) { monitor.disconnect() } }
                if !monitor.configuration.serial.isEmpty { Button(L("printer.forget")) { monitor.forget(); code = ""; host = ""; serial = "" } }
            }
            Label(monitor.label, systemImage: "printer").font(Design.value).foregroundStyle(Design.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(L("printer.findSettings")) {
                VStack(alignment: .leading, spacing: Design.small) {
                    Text(L("printer.whereSettings"))
                    Text(L("printer.modeHint"))
                    Link(L("printer.manualLink"), destination: URL(string: "https://csm.bblcdn.com/hub/7c58718aaa2e40edab56efb87419a96a.pdf#page=101")!)
                }.font(Design.caption).foregroundStyle(Design.secondary).padding(.top, Design.small)
            }
        }.onAppear { host = monitor.configuration.host; serial = monitor.configuration.serial }
    }
}

struct PrinterStatusCard: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var monitor: PrinterMonitor
    var record: (ShelfItem) -> Void
    @State private var itemID = ""
    @State private var startedAt = Date()
    @State private var binding = false
    private var availableItems: [ShelfItem] { model.queuedItems.filter { model.activePrint == nil || model.activePrint?.id == $0.id } }
    private var boundItem: ShelfItem? { model.queuedItems.first { monitor.completionSession(itemID: $0.id) != nil } }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: Design.small) {
                HStack {
                    Label(L("printer.title"), systemImage: "printer").font(Design.value)
                    Spacer()
                    Button(L(monitor.configuration.valid ? "settings" : "printer.connectTitle")) { model.showSettings = true }.buttonStyle(.link)
                }
                if monitor.configuration.valid {
                    Text(monitor.label).font(Design.value).foregroundStyle(Design.accent).fixedSize(horizontal: false, vertical: true)
                    if monitor.snapshot.fresh(at: context.date), monitor.snapshot.state.active || monitor.snapshot.state.terminal {
                        if !monitor.snapshot.jobName.isEmpty { Text(monitor.snapshot.jobName).lineLimit(2) }
                        if let percent = monitor.snapshot.progress {
                            HStack {
                                ProgressView(value: percent, total: 100).frame(maxWidth: 220)
                                Text(String(format: "%.0f%%", percent)).monospacedDigit().font(Design.caption)
                                if let remaining = monitor.snapshot.remaining(at: context.date) {
                                    Text(String(format: L("printer.remaining"), timeText(remaining))).font(Design.caption)
                                }
                            }
                        }
                        if let item = boundItem {
                            HStack {
                                Text(String(format: L("printer.bound"), item.title)).font(Design.caption).lineLimit(2)
                                Spacer()
                                if monitor.session?.terminalState != nil { Button(L("queue.complete")) { record(item) }.buttonStyle(.borderedProminent).tint(Design.action).foregroundStyle(.white) }
                                Button(L("printer.unlink")) { monitor.unbind(itemID: item.id) }.buttonStyle(.link)
                            }
                            if monitor.session?.endNeedsReview == true { Text(L("printer.endReview")).font(Design.caption).foregroundStyle(Design.warning) }
                        } else if monitor.session?.recorded != true, !availableItems.isEmpty {
                            DisclosureGroup(L("printer.matchJob")) {
                                VStack(alignment: .leading, spacing: Design.small) {
                                    Text(L("printer.matchHint")).font(Design.caption).foregroundStyle(Design.secondary)
                                    Picker(L("printer.queueItem"), selection: $itemID) {
                                        Text(L("printer.chooseItem")).tag("")
                                        ForEach(availableItems) { Text($0.title).tag($0.id) }
                                    }.onChange(of: itemID) { _ in prepareStart() }
                                    DatePicker(L("record.startedAt"), selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                                    Text(L("printer.startHint")).font(Design.caption).foregroundStyle(Design.secondary)
                                    Button(L("printer.bind")) {
                                        guard let item = availableItems.first(where: { $0.id == itemID }) else { return }
                                        binding = true
                                        Task { _ = await model.bindPrinterJob(item, startedAt: startedAt); binding = false }
                                    }.disabled(itemID.isEmpty || binding || model.isWorking || startedAt >= (monitor.session?.endedAt ?? Date()))
                                }.padding(.top, Design.small)
                            }
                        }
                    } else { Text(L("printer.liveHint")).font(Design.caption).foregroundStyle(Design.secondary) }
                } else { Text(L("printer.connectHint")).font(Design.caption).foregroundStyle(Design.secondary) }
            }.padding(Design.regular)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Design.cardRadius).stroke(Design.divider))
        }
    }
    private func prepareStart() {
        startedAt = monitor.session?.startedAt ?? model.printQueue.first { $0.id == itemID }?.startedAt ?? Date()
    }
}
