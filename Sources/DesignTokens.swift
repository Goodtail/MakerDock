import SwiftUI
import AppKit
import PlateShelfCore

func L(_ key: String) -> String { ShelfLocalization.text(key, bundle: .main) }
func dateText(_ date: Date) -> String { date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: ShelfLocalization.locale)) }
func plateTitle(_ plate: PlateRecord) -> String {
    if plate.name.isEmpty || plate.name == "플레이트 \(plate.id)" || plate.name == "Plate \(plate.id)" { return String(format: L("plate.number"), plate.id) }
    return plate.name
}
enum ShelfAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { L("appearance." + rawValue) }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    static func scheme(for value: String) -> ColorScheme? {
        (Self(rawValue: value) ?? .system).colorScheme
    }
    @MainActor static func apply(_ value: String) {
        switch Self(rawValue: value) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Design {
    static let action = Color("ShelfAction"), shadow = Color("ShelfShadow")
    static let accent = Color("ShelfAccent"), canvas = Color("ShelfCanvas"), surface = Color("ShelfSurface"), preview = Color("ShelfPreview"), ink = Color("ShelfInk"), secondary = Color("ShelfSecondary"), divider = Color("ShelfDivider"), warning = Color("ShelfWarning")
    static let sidebarSurface = Color("ShelfSidebar"), selection = Color("ShelfSelection")
    static let title = Font.system(size: 24, weight: .semibold), detailTitle = Font.system(size: 20, weight: .semibold), heading = Font.system(size: 15, weight: .semibold), body = Font.system(size: 13), value = Font.system(size: 13, weight: .medium), caption = Font.system(size: 11)
    static let tiny: CGFloat = 4, small: CGFloat = 8, medium: CGFloat = 12, regular: CGFloat = 16, large: CGFloat = 24, xlarge: CGFloat = 32, jumbo: CGFloat = 48, hero: CGFloat = 64
    static let cardRadius: CGFloat = 12, imageRadius: CGFloat = 8, controlRadius: CGFloat = 6
    static let sidebar: CGFloat = 216, inspector: CGFloat = 320, imageHeight: CGFloat = 160, cardMin: CGFloat = 208, cardMax: CGFloat = 280
    static let windowMinWidth: CGFloat = 1040, windowMinHeight: CGFloat = 680, windowWidth: CGFloat = 1320, windowHeight: CGFloat = 860
    static let plateThumbnail: CGFloat = 80, zoomWidth: CGFloat = 800, zoomHeight: CGFloat = 660
}
func timeText(_ seconds: Double?) -> String {
    guard let seconds, seconds > 0 else { return L("estimate.missing") }
    let mins = max(1, Int((seconds / 60).rounded()))
    return mins >= 60 ? String(format: L("time.hoursMinutes"), mins / 60, mins % 60) : String(format: L("time.minutes"), mins)
}
func weightText(_ grams: Double?) -> String {
    guard let grams, grams > 0 else { return "—" }
    return grams.formatted(.number.locale(ShelfLocalization.locale).precision(.fractionLength(1))) + " g"
}
