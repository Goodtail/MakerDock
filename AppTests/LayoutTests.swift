import XCTest
import SwiftUI
import PlateShelfCore
@testable import PlateShelf

final class LayoutTests: XCTestCase {
    @MainActor func testCompletionTimingAndConnectionFieldsFit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let end = Date().addingTimeInterval(-60)
        let draft = PrintDetailsDraft(estimate: PrintEstimate(seconds: 10380, source: .file), filaments: [FilamentRecord(name: "Bambu PLA Matte", material: "PLA", color: "000000FF", grams: 85.13)], startedAt: end.addingTimeInterval(-14_400), completedAt: end)
        let views: [(String, AnyView, CGFloat)] = [
            ("completion-timing", AnyView(PrintDetailsFields(draft: .constant(draft))), 430),
            ("printer-connection", AnyView(PrinterConnectionSettings(model: model, monitor: model.printerMonitor)), 500)
        ]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MakerDock-LayoutQA.noindex")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, view, height) in views {
            let host = NSHostingView(rootView: view.padding(24).frame(width: 620, height: height, alignment: .topLeading).background(Design.surface).foregroundStyle(Design.ink).font(Design.body).environment(\.locale, Locale(identifier: "ko")).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, 620)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
            window.close()
        }
    }
    @MainActor func testLibraryAndQueueFitNarrowWindows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let item = ShelfItem(id: "layout", title: "Glasshook Bathroomhook Showerhook 6/8/10 mm", filename: "Hook.3mf", filePath: "Files/Hook.3mf", plates: [PlateRecord(id: "1", name: "Plate 1", estimatedSeconds: 1652)])
        model.items = [item]; model.selectionID = item.id
        model.printQueue = [PrintQueueEntry(id: item.id, startedAt: Date().addingTimeInterval(-600), startedDurationSeconds: 1652)]
        let captures = FileManager.default.temporaryDirectory.appendingPathComponent("MakerDock-LayoutQA.noindex")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        for filter: ShelfFilter in [.all, .queue] {
            model.filter = filter
            for width: CGFloat in [860, 1040] {
                let host = NSHostingView(rootView: ContentView(model: model).environment(\.locale, Locale(identifier: "ko")).preferredColorScheme(.dark))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.setContentSize(NSSize(width: width, height: 700))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 150_000_000)
                host.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.width, width, "The view's minimum width must fit the window")
                XCTAssertEqual(host.bounds.width, width, accuracy: 1)
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try data.write(to: captures.appendingPathComponent("\(filter == .queue ? "queue" : "library")-\(Int(width)).png"))
                window.close()
            }
        }
    }
}
