import XCTest
import SwiftUI
import PlateShelfCore
@testable import PlateShelf

final class LayoutTests: XCTestCase {
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
