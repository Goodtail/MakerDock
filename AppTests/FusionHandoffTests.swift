import XCTest
import CryptoKit
@testable import PlateShelf

final class FusionHandoffTests: XCTestCase {
    func testProtocolOpensSeparateDesignAndEncodesLocalPath() throws {
        let file = URL(fileURLWithPath: "/tmp/메이커 독/part + #1 & 50%.stl")
        let url = try FusionHandoff.openURL(for: file)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "fusion360")
        XCTAssertEqual(components.host, "host")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "command", value: "open"), URLQueryItem(name: "file", value: file.path)])
        XCTAssertFalse(url.absoluteString.contains("+"))
        XCTAssertThrowsError(try FusionHandoff.openURL(for: URL(string: "https://example.com/model.stl")!))
        XCTAssertThrowsError(try FusionHandoff.openURL(for: URL(fileURLWithPath: "/tmp/model.3mf")))
    }
    func testExportDoesNotSliceOrSendPrinterCommands() {
        let input = URL(fileURLWithPath: "/tmp/input.3mf"), output = URL(fileURLWithPath: "/tmp/out"), settings = URL(fileURLWithPath: "/tmp/settings")
        let args = FusionMeshExporter.arguments(input: input, output: output, settings: settings)
        XCTAssertTrue(args.contains("--export-stl"))
        XCTAssertEqual(args.last, input.path)
        XCTAssertTrue(Set(args).isDisjoint(with: ["--slice", "--load-custom-gcodes", "--load-settings", "--orient", "--arrange"]))
    }
    func testRejectsTruncatedMeshAndSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var data = Data(repeating: 0, count: 134); data[80] = 2 // Declares two triangles, contains only one.
        let file = root.appendingPathComponent("broken.stl")
        try data.write(to: file)
        let exporter = FusionMeshExporter()
        do { _ = try await exporter.meshes(in: root); XCTFail("Truncated mesh accepted") } catch {}
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        do { _ = try await exporter.meshes(in: root); XCTFail("Symlink accepted") } catch {}
    }
    func testInstalledStudioExportsMultipleModelsAndReusesCompleteCache() async throws {
        let studio = URL(fileURLWithPath: "/Applications/BambuStudio.app")
        guard Bundle(url: studio)?.bundleIdentifier == "com.bambulab.bambu-studio" else { throw XCTSkip("Official Studio is not installed") }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FusionModels", withExtension: "3mf"))
        let original = try Data(contentsOf: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = FusionMeshExporter()
        let meshes = try await exporter.export(input: source, studio: studio, cacheRoot: root)
        XCTAssertEqual(meshes.count, 2)
        let paths = meshes.map(\.url)
        let firstDates = try paths.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let cached = try await exporter.export(input: source, studio: studio, cacheRoot: root)
        XCTAssertEqual(cached.map(\.url), paths)
        XCTAssertEqual(try paths.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }, firstDates)
        XCTAssertEqual(try Data(contentsOf: source), original)
        // A missing part must regenerate the complete model set, not silently open a partial cache.
        try FileManager.default.removeItem(at: paths[0])
        let repaired = try await exporter.export(input: source, studio: studio, cacheRoot: root)
        XCTAssertEqual(repaired.count, 2)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
