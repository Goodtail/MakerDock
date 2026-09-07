import SwiftUI
import PlateShelfCore

struct PrintEstimate: Equatable {
    enum Source { case makerWorld, file, myPrinter }
    let seconds: Double
    let source: Source
    var sourceLabel: String { source == .makerWorld ? "MakerWorld" : source == .file ? "3MF" : "내 프린터" }
    var explanation: String {
        source == .makerWorld ? "보관 당시 MakerWorld 출력 프로필의 예상 시간" : source == .file ? "3MF에 저장된 슬라이싱 예상 시간" : "선택한 프린터로 공식 Studio에서 계산한 예상 시간"
    }
    static func valid(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}

extension ShelfItem {
    var preferredEstimate: PrintEstimate? {
        if let seconds = PrintEstimate.valid(makerWorldSource?.estimatedSeconds) ?? PrintEstimate.valid(makerWorldSource?.knownPlateEstimatedSeconds) {
            return PrintEstimate(seconds: seconds, source: .makerWorld)
        }
        return PrintEstimate.valid(estimatedSeconds).map { PrintEstimate(seconds: $0, source: .file) }
    }

    func preferredEstimate(for plate: PlateRecord) -> PrintEstimate? {
        if let web = makerWorldSource {
            // A profile total identifies a plate only when both sources contain exactly one plate.
            if plates.count == 1, web.plateCount == 1,
               let seconds = PrintEstimate.valid(web.estimatedSeconds) ?? PrintEstimate.valid(web.knownPlateEstimatedSeconds) {
                return PrintEstimate(seconds: seconds, source: .makerWorld)
            }
            if let webPlates = web.plates, web.plateCount == plates.count,
               Set(webPlates.map(\.id)) == Set(plates.map(\.id)),
               let seconds = PrintEstimate.valid(webPlates.first(where: { $0.id == plate.id })?.estimatedSeconds) {
                return PrintEstimate(seconds: seconds, source: .makerWorld)
            }
        }
        return PrintEstimate.valid(plate.estimatedSeconds).map { PrintEstimate(seconds: $0, source: .file) }
    }
}

struct EstimateLabel: View {
    let estimate: PrintEstimate?
    var missing = "예상 시간 없음"
    var body: some View {
        HStack(spacing: Design.tiny) {
            Image(systemName: "clock")
            Text(estimate.map { timeText($0.seconds) } ?? missing)
                .fontWeight(estimate == nil ? .regular : .medium).monospacedDigit()
            if let estimate { Text("· " + estimate.sourceLabel).foregroundStyle(Design.secondary) }
        }.font(Design.caption).foregroundStyle(estimate == nil ? Design.secondary : Design.ink)
            .help(estimate?.explanation ?? "MakerWorld와 3MF에 저장된 예상 시간이 없습니다.")
    }
}
