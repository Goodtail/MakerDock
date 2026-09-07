import SwiftUI
import PlateShelfCore

struct FilamentDraft: Identifiable {
    var id = UUID().uuidString
    var name = ""
    var material = ""
    var color: String?
    var grams = ""
    init(_ value: FilamentRecord = FilamentRecord()) {
        name = value.name; material = value.material; color = value.color
        if let g = value.grams { grams = Self.number.string(from: NSNumber(value: g)) ?? "" }
    }
    static var number: NumberFormatter {
        let f = NumberFormatter(); f.locale = ShelfLocalization.locale; f.numberStyle = .decimal; f.maximumFractionDigits = 3
        f.usesGroupingSeparator = false; return f
    }
    var amount: Double? {
        let text = grams.trimmingCharacters(in: .whitespacesAndNewlines)
        // Decimal input only: reject trailing text rather than accepting a partial number.
        let separator = Self.number.decimalSeparator ?? "."
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        return Double(normalized)
    }
    var valid: Bool { grams.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (amount != nil && amount!.isFinite && amount! >= 0) }
    var record: FilamentRecord { FilamentRecord(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), material: material.trimmingCharacters(in: .whitespacesAndNewlines), color: color, grams: amount) }
}

struct PrintDetailsDraft {
    var hours = ""
    var minutes = ""
    var filaments: [FilamentDraft] = []
    var prefill: PrintEstimate?
    private var originalHours = "", originalMinutes = ""
    init(estimate: PrintEstimate? = nil, filaments: [FilamentRecord] = []) {
        prefill = estimate
        if let estimate {
            let total = Int(min(6_000_000, max(1, (estimate.seconds / 60).rounded())))
            hours = String(total / 60); minutes = String(total % 60)
        }
        originalHours = hours; originalMinutes = minutes
        self.filaments = filaments.map(FilamentDraft.init)
    }
    var timeUnchanged: Bool { hours == originalHours && minutes == originalMinutes }
    var seconds: Double? {
        if timeUnchanged, let prefill { return prefill.seconds }
        let h = Int(hours.trimmingCharacters(in: .whitespaces)) ?? 0, m = Int(minutes.trimmingCharacters(in: .whitespaces)) ?? 0
        guard h >= 0, h <= 100_000, m >= 0, m < 60 else { return nil }
        let value = h * 3600 + m * 60
        return value > 0 ? Double(value) : nil
    }
    var valid: Bool {
        let h = hours.trimmingCharacters(in: .whitespaces), m = minutes.trimmingCharacters(in: .whitespaces)
        let empty = h.isEmpty && m.isEmpty
        let validTime = empty || ((h.isEmpty || Int(h) != nil) && (m.isEmpty || Int(m) != nil) && seconds != nil)
        return validTime && filaments.allSatisfy(\.valid)
    }
    var durationSource: String? {
        guard seconds != nil else { return nil }
        if timeUnchanged, let prefill { return prefill.source == .makerWorld ? "makerWorld" : prefill.source == .file ? "file" : "myPrinter" }
        return "manual"
    }
    var records: [FilamentRecord] { filaments.map(\.record).filter { !$0.name.isEmpty || !$0.material.isEmpty || $0.grams != nil } }
}

extension LibraryViewModel {
    func printDetails(_ item: ShelfItem) -> PrintDetailsDraft {
        let plates = savedEstimate(item)?.plates ?? item.plates
        var values: [FilamentRecord] = []
        let complete = !plates.isEmpty && plates.allSatisfy { !($0.filaments ?? []).isEmpty }
        for filament in plates.flatMap({ $0.filaments ?? [] }) {
            if let i = values.firstIndex(where: { $0.id == filament.id && $0.material == filament.material && $0.color == filament.color }) {
                values[i].grams = complete && values[i].grams != nil && filament.grams != nil ? values[i].grams! + filament.grams! : nil
            } else {
                var value = filament
                if !complete { value.grams = nil }
                values.append(value)
            }
        }
        if values.isEmpty {
            values = item.filaments ?? []
            if values.isEmpty { values = item.materials.map { FilamentRecord(material: $0) } }
            if values.count == 1, plates.count > 0, plates.allSatisfy({ $0.weightGrams != nil }) {
                values[0].grams = plates.compactMap(\.weightGrams).reduce(0, +)
            }
        }
        return PrintDetailsDraft(estimate: displayedEstimate(item), filaments: values)
    }
}

struct PrintDetailsFields: View {
    @Binding var draft: PrintDetailsDraft
    var body: some View {
        VStack(alignment: .leading, spacing: Design.small) {
            Text(L("record.duration")).font(Design.value)
            HStack {
                TextField("0", text: $draft.hours).frame(width: 64).accessibilityLabel(L("record.hours"))
                Text(L("record.hours"))
                TextField("0", text: $draft.minutes).frame(width: 64).accessibilityLabel(L("record.minutes"))
                Text(L("record.minutes"))
                Spacer()
                if let estimate = draft.prefill { Button(L("record.useEstimate")) { let f = draft.filaments; draft = PrintDetailsDraft(estimate: estimate); draft.filaments = f }.buttonStyle(.link) }
            }.textFieldStyle(.roundedBorder)
            if let estimate = draft.prefill {
                Text(String(format: L("record.prefill"), estimate.sourceLabel, timeText(estimate.seconds))).font(Design.caption).foregroundStyle(Design.secondary)
            } else { Text(L("record.optionalTime")).font(Design.caption).foregroundStyle(Design.secondary) }
            HStack { Text(L("record.filaments")).font(Design.value); Spacer(); Button { draft.filaments.append(FilamentDraft()) } label: { Label(L("record.addFilament"), systemImage: "plus") }.buttonStyle(.link) }
                .padding(.top, Design.small)
            ForEach($draft.filaments) { $filament in
                HStack(spacing: Design.small) {
                    if let hex = filament.color, let color = filamentColor(hex) { Circle().fill(color).frame(width: 16, height: 16).overlay(Circle().stroke(Design.divider)).help(hex) }
                    TextField(L("record.filamentName"), text: $filament.name)
                    TextField(L("material"), text: $filament.material).frame(width: 82)
                    TextField(L("record.amount"), text: $filament.grams).frame(width: 72)
                    Text("g").foregroundStyle(Design.secondary)
                    Button { draft.filaments.removeAll { $0.id == filament.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help(L("record.removeFilament"))
                }.textFieldStyle(.roundedBorder)
            }
            Text(L("record.filamentHint")).font(Design.caption).foregroundStyle(Design.secondary)
            if !draft.valid { Text(L("record.invalid")).font(Design.caption).foregroundStyle(Design.warning) }
        }
    }
}

func filamentColor(_ hex: String) -> Color? {
    let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard [6, 8].contains(value.count), let rgb = UInt64(value.prefix(6), radix: 16) else { return nil }
    return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
}
