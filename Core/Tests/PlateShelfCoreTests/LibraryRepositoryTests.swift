import XCTest
import Foundation
import ZIPFoundation
@testable import PlateShelfCore

final class LibraryRepositoryTests: XCTestCase {
    var temp: URL!
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=")!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("PlateShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }

    func fixture(_ name: String = "Sample.3mf", changes: [String: Data] = [:], removed: Set<String> = []) throws -> URL {
        var entries: [String: Data] = [
            "[Content_Types].xml": Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"model\" ContentType=\"application/vnd.ms-package.3dmanufacturing-3dmodel+xml\"/></Types>".utf8),
            "3D/3dmodel.model": Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <m:model xmlns:m="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:BambuStudio="http://schemas.bambulab.com/package/2021">
              <m:metadata name="Title">컵 &amp; 선반</m:metadata>
              <m:metadata name="Designer">Creator</m:metadata>
              <m:metadata name="Thumbnail_Middle">/Metadata/plate_1.png</m:metadata>
              <m:resources/><m:build/>
              <m:metadata name="DesignModelId">US123abc</m:metadata>
              <m:metadata name="DesignProfileId">456</m:metadata>
              <m:metadata name="ProfileTitle">0.2 mm / PLA</m:metadata>
            </m:model>
            """.utf8),
            "Metadata/model_settings.config": Data("""
            <config><plate>
              <metadata key="plater_id" value="2"/><metadata key="plater_name" value="뚜껑"/>
              <metadata key="thumbnail_file" value="Metadata/plate_2.png"/>
              <model_instance><metadata key="name" value="Do not use this"/><metadata key="plater_id" value="99"/></model_instance>
            </plate><plate>
              <metadata key="plater_id" value="1"/><metadata key="plater_name" value="본체"/>
              <metadata key="thumbnail_file" value="Metadata/plate_1.png"/>
            </plate></config>
            """.utf8),
            "Metadata/slice_info.config": Data("""
            <config><header><header_item key="X-BBL-Client-Type" value="slicer"/></header>
            <plate><metadata key="index" value="1"/><metadata key="prediction" value="3600"/>
              <metadata key="weight" value="20.5"/><filament id="1" type="PLA" used_g="20.5"/></plate>
            <plate><metadata key="index" value="2"/><metadata key="prediction" value="1200"/>
              <metadata key="weight" value="9.5"/></plate></config>
            """.utf8),
            "Metadata/project_settings.config": Data("{\"filament_type\":[\"PLA\",\"PETG\",\"PLA\"],\"printer_model\":\"Bambu Lab P2S\"}".utf8),
            "Metadata/plate_1.png": png, "Metadata/plate_2.png": png,
            "Metadata/plate_1.gcode": Data("G28\n".utf8)
        ]
        for path in removed { entries.removeValue(forKey: path) }
        entries.merge(changes) { _, replacement in replacement }
        let url = temp.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    func repository(_ suffix: String = "Library") throws -> LibraryRepository {
        try LibraryRepository(rootURL: temp.appendingPathComponent(suffix))
    }

    func testNamespaceMetadataPlateMappingAndManagedPreviews() async throws {
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let repo = try repository()
        let result = try await repo.importFile(at: source)
        let item = result.item
        XCTAssertFalse(result.isDuplicate)
        XCTAssertEqual(item.title, "컵 & 선반")
        XCTAssertEqual(item.designer, "Creator")
        XCTAssertEqual(item.modelID, "US123abc")
        XCTAssertEqual(item.profileID, "456")
        XCTAssertEqual(item.profileTitle, "0.2 mm / PLA")
        XCTAssertEqual(item.materials, ["PETG", "PLA"])
        XCTAssertEqual(item.printerModel, "Bambu Lab P2S")
        XCTAssertEqual(item.plates.map(\.id), ["2", "1"])
        XCTAssertEqual(item.plates.map(\.name), ["뚜껑", "본체"])
        XCTAssertEqual(item.plates.map(\.estimatedSeconds), [1200, 3600])
        XCTAssertEqual(item.estimatedSeconds, 4800)
        XCTAssertEqual(item.weightGrams, 30)
        XCTAssertTrue(item.hasGCode)
        XCTAssertEqual(item.id.count, 64)
        XCTAssertEqual(try Data(contentsOf: repo.rootURL.appendingPathComponent(item.filePath)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let preview = try XCTUnwrap(item.thumbnailPath)
        XCTAssertTrue(preview.hasPrefix("Previews/"))
        XCTAssertEqual(try Data(contentsOf: repo.rootURL.appendingPathComponent(preview)), png)
        XCTAssertEqual(item.plates[0].thumbnailPath, item.plates[1].thumbnailPath)
    }

    func testDuplicatePreservesUserMetadataAndSourcesAcrossRelaunch() async throws {
        let source = try fixture()
        let renamed = temp.appendingPathComponent("Sample(2).3mf")
        try FileManager.default.copyItem(at: source, to: renamed)
        let repo = try repository()
        let first = try await repo.importFile(at: source).item
        try await repo.updateUserMetadata(id: first.id, tags: [" 책상 ", "책상", "", "선물"], favorite: true, note: "내 메모")
        let second = try await repo.importFile(at: renamed)
        XCTAssertTrue(second.isDuplicate)
        XCTAssertEqual(second.item.id, first.id)
        XCTAssertEqual(Set(second.item.sourcePaths), Set([source.path, renamed.path]))
        XCTAssertEqual(second.item.tags, ["책상", "선물"])
        XCTAssertTrue(second.item.favorite)
        XCTAssertEqual(second.item.note, "내 메모")
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let items = await reopened.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].note, "내 메모")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent("Files").path).count, 1)
    }

    func testRunsUpsertStableIDAndPreserveManualRun() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        try await repo.appendRun(itemID: item.id, run: PrintRun(id: "manual", status: "manual", source: "user", note: "좋음"))
        try await repo.appendRun(itemID: item.id, run: PrintRun(id: "studio-1", status: "prepared", source: "studio"))
        try await repo.appendRun(itemID: item.id, run: PrintRun(id: "studio-1", status: "submitted", source: "studio"))
        let runs = await repo.items()[0].printRuns
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].note, "좋음")
        XCTAssertEqual(runs[1].status, "submitted")
    }

    func testHeaderOnlyAndPartialEstimatesNeverBecomeZeroTotals() async throws {
        let repo = try repository()
        let source = try fixture(changes: ["Metadata/slice_info.config": Data("<config><header/></config>".utf8)])
        let item = try await repo.importFile(at: source).item
        XCTAssertNil(item.estimatedSeconds)
        XCTAssertNil(item.weightGrams)
        XCTAssertTrue(item.plates.allSatisfy { $0.estimatedSeconds == nil })
        let partial = try fixture("Partial.3mf", changes: ["Metadata/slice_info.config": Data("<config><plate><metadata key=\"index\" value=\"2\"/><metadata key=\"prediction\" value=\"200\"/><metadata key=\"weight\" value=\"0\"/></plate></config>".utf8)])
        let second = try await repo.importFile(at: partial).item
        XCTAssertEqual(second.plates[0].estimatedSeconds, 200)
        XCTAssertNil(second.estimatedSeconds)
        XCTAssertNil(second.weightGrams)
    }

    func testGCodeHeaderRecoversMissingTimeWithoutOverridingSliceMetadata() async throws {
        let file = try fixture(changes: [
            "Metadata/slice_info.config": Data("<config><header/></config>".utf8),
            "Metadata/plate_1.gcode": Data("; model printing time: 19m 33s; total estimated time: 26m 54s\nG28\n".utf8),
            "Metadata/plate_2.gcode": Data("; estimated printing time (normal mode) = 1h 2m 3s\nG28\n".utf8)
        ])
        let summary = try ArchivePrintSummary.read(at: file)
        XCTAssertEqual(summary.plates.map(\.estimatedSeconds), [3723, 1614])
        let withSlice = try fixture("WithSlice.3mf", changes: ["Metadata/plate_1.gcode": Data("; model printing time: 1m; total estimated time: 2m\n".utf8)])
        XCTAssertEqual(try ArchivePrintSummary.read(at: withSlice).plates.first { $0.id == "1" }?.estimatedSeconds, 3600)
    }

    func testGCodeTimeDoesNotInventDurationFromCommandsOrInvalidText() {
        XCTAssertNil(ThreeMFReader.gcodeHeaderTime("M73 P0 R120\n; model printing time: 15m\n"))
        XCTAssertNil(ThreeMFReader.gcodeHeaderTime("; total estimated time: -12m"))
        XCTAssertNil(ThreeMFReader.gcodeHeaderTime("; total estimated time: 0s"))
        XCTAssertNil(ThreeMFReader.gcodeHeaderTime("; total estimated time: 12m fake"))
        XCTAssertEqual(ThreeMFReader.gcodeHeaderTime("; total estimated time: 1d 2h 3m 4s"), 93784)
    }

    func testRejectsUnsafeArchiveAndMetadataPathsWithoutWriting() async throws {
        for (number, path) in ["../escape", "/absolute", "Metadata/../../escape", "C:\\escape"].enumerated() {
            let repo = try repository("Library\(number)")
            let file = try fixture("Malicious\(number).3mf", changes: [path: Data("bad".utf8)])
            do { _ = try await repo.importFile(at: file); XCTFail("Accepted \(path)") }
            catch LibraryError.unsafePath { }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent("Files").path), [])
        }
        let metadata = Data("<config><plate><metadata key=\"plater_id\" value=\"1\"/><metadata key=\"thumbnail_file\" value=\"../escape.png\"/></plate></config>".utf8)
        let repo = try repository("MetadataPaths")
        do { _ = try await repo.importFile(at: fixture("Metadata.3mf", changes: ["Metadata/model_settings.config": metadata])); XCTFail("Accepted escaped preview") }
        catch LibraryError.unsafePath { }
    }

    func testRejectsSymlinkArchiveEntry() async throws {
        let file = try fixture()
        let archive = try Archive(url: file, accessMode: .update)
        let data = Data("/etc/passwd".utf8)
        try archive.addEntry(with: "Metadata/link", type: .symlink, uncompressedSize: Int64(data.count)) { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        let repo = try repository()
        do { _ = try await repo.importFile(at: file); XCTFail("Accepted symbolic link") }
        catch LibraryError.unsafePath { }
    }

    func testRejectsExternalEntitiesAndMalformedXML() async throws {
        let repo = try repository()
        let xxe = Data("<?xml version=\"1.0\"?><!DOCTYPE model [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><model><metadata name=\"Title\">&x;</metadata></model>".utf8)
        for (index, xml) in [xxe, Data("<model><broken></model>".utf8)].enumerated() {
            do { _ = try await repo.importFile(at: fixture("XML\(index).3mf", changes: ["3D/3dmodel.model": xml])); XCTFail("Accepted malformed XML") }
            catch LibraryError.invalidXML { }
        }
        let items = await repo.items()
        XCTAssertTrue(items.isEmpty)
    }

    func testRejectsOversizedMetadataAndSkipsPixelBombPreview() async throws {
        let repo = try repository()
        let huge = Data(repeating: 32, count: ArchiveLimits.settingsBytes + 1)
        do { _ = try await repo.importFile(at: fixture("Huge.3mf", changes: ["Metadata/project_settings.config": huge])); XCTFail("Accepted oversized settings") }
        catch LibraryError.limitExceeded { }
        var bomb = png
        bomb.replaceSubrange(16..<24, with: [255,255,255,255,255,255,255,255])
        let item = try await repo.importFile(at: fixture("Image.3mf", changes: ["Metadata/plate_1.png": bomb, "Metadata/plate_2.png": bomb])).item
        XCTAssertNil(item.thumbnailPath)
        XCTAssertTrue(item.plates.allSatisfy { $0.thumbnailPath == nil })
    }

    func testCorruptIndexPreservedAtOpenAndAfterOpen() async throws {
        let root = temp.appendingPathComponent("Corrupt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent("index.json")
        let corrupted = Data("do not overwrite".utf8)
        try corrupted.write(to: index)
        XCTAssertThrowsError(try LibraryRepository(rootURL: root))
        XCTAssertEqual(try Data(contentsOf: index), corrupted)
        let repo = try repository()
        let first = try await repo.importFile(at: fixture()).item
        try corrupted.write(to: repo.rootURL.appendingPathComponent("index.json"))
        do { try await repo.updateUserMetadata(id: first.id, tags: [], favorite: true, note: "new"); XCTFail("Overwrote external edit") }
        catch LibraryError.libraryChanged { }
        let items = await repo.items()
        XCTAssertFalse(items[0].favorite)
        XCTAssertEqual(try Data(contentsOf: repo.rootURL.appendingPathComponent("index.json")), corrupted)
        let newFile = try fixture("Another.3mf", changes: ["Metadata/plate_1.gcode": Data("G28\nG1 X1".utf8)])
        do { _ = try await repo.importFile(at: newFile); XCTFail("Committed into corrupted index") }
        catch LibraryError.libraryChanged { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent("Files").path).count, 1)
    }

    func testRejectsNon3MFZipAndBadChecksum() async throws {
        let repo = try repository()
        do { _ = try await repo.importFile(at: fixture("Not3MF.3mf", removed: ["[Content_Types].xml"])); XCTFail("Accepted arbitrary ZIP") }
        catch LibraryError.invalidArchive { }
        let file = temp.appendingPathComponent("Checksum.3mf")
        do {
            let zip = try Archive(url: file, accessMode: .create)
            for (path, body) in [("[Content_Types].xml", "<Types/>"), ("3D/3dmodel.model", "<model><metadata name=\"Title\">CheckSumOriginal</metadata></model>")] {
                let data = Data(body.utf8)
                try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in data.subdata(in: Int(offset)..<Int(offset) + size) }
            }
        }
        var bytes = try Data(contentsOf: file)
        let range = try XCTUnwrap(bytes.range(of: Data("CheckSumOriginal".utf8)))
        bytes[range.lowerBound] = UInt8(ascii: "X")
        try bytes.write(to: file)
        do { _ = try await repo.importFile(at: file); XCTFail("Accepted corrupt checksum") }
        catch LibraryError.invalidArchive { }
    }

    func testActualSamplesWhenExplicitlyConfigured() async throws {
        guard let folder = ProcessInfo.processInfo.environment["PLATESHELF_SAMPLE_DIR"] else { throw XCTSkip("Set PLATESHELF_SAMPLE_DIR for read-only real-file validation") }
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "3mf" }
        let repo = try repository()
        var duplicateCount = 0
        var sourceHashes = Set<String>()
        for url in urls {
            let before = try LibraryRepository.hashFile(url)
            sourceHashes.insert(before)
            let imported = try await repo.importFile(at: url)
            if imported.isDuplicate { duplicateCount += 1 }
            XCTAssertNotNil(imported.item.thumbnailPath, url.lastPathComponent)
            XCTAssertNotNil(imported.item.modelID, url.lastPathComponent)
            XCTAssertNotNil(imported.item.profileID, url.lastPathComponent)
            XCTAssertEqual(try LibraryRepository.hashFile(url), before)
        }
        let all = await repo.items()
        print("Real sample validation: \(urls.count) archives, \(all.count) unique, \(duplicateCount) duplicate imports, \(all.filter { $0.estimatedSeconds != nil }.count) complete estimates")
        XCTAssertFalse(urls.isEmpty)
        XCTAssertEqual(all.count, sourceHashes.count)
        XCTAssertEqual(duplicateCount, urls.count - sourceHashes.count)
    }

    func testAtomicMetadataUpdatesPreserveIndependentEdits() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        async let text: Void = repo.updateTagsAndNote(id: item.id, tags: [" 새 태그 ", "새 태그"], note: "새 메모")
        async let favorite: Void = repo.toggleFavorite(id: item.id)
        _ = try await (text, favorite)
        var current = await repo.items()[0]
        XCTAssertEqual(current.tags, ["새 태그"])
        XCTAssertEqual(current.note, "새 메모")
        XCTAssertTrue(current.favorite)
        async let toggleOne: Void = repo.toggleFavorite(id: item.id)
        async let toggleTwo: Void = repo.toggleFavorite(id: item.id)
        _ = try await (toggleOne, toggleTwo)
        current = await repo.items()[0]
        XCTAssertTrue(current.favorite)
        XCTAssertEqual(current.note, "새 메모")
    }

    func testWebSourceIsSeparateCanonicalAndSurvivesDedupAndRelaunch() async throws {
        let repo = try repository()
        let file = try fixture()
        let item = try await repo.importFile(at: file).item
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let source = MakerWorldSource(pageURL: "https://makerworld.com/ko/models/1099461-sturdy-modular-filament-spool-rack-fully-printable?from=search&token=secret",
                                     profileURL: "https://makerworld.com/ko/models/1099461-sturdy-modular-filament-spool-rack-fully-printable?signature=private#profileId-1791619",
                                     capturedAt: capturedAt, title: "웹에서 읽은 제목", profileTitle: "웹 프로필",
                                     estimatedSeconds: 7200, plateCount: 1,
                                     plates: [WebPlateRecord(id: "web-1", name: "전체", estimatedSeconds: 7200, weightGrams: 52.3, plateType: "Textured PEI Plate")])
        try await repo.updateSource(id: item.id, source: source)
        let duplicate = try await repo.importFile(at: file)
        XCTAssertEqual(duplicate.item.estimatedSeconds, 4800)
        XCTAssertEqual(duplicate.item.makerWorldSource?.estimatedSeconds, 7200)
        XCTAssertEqual(duplicate.item.makerWorldSource?.capturedAt, capturedAt)
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let reopenedItems = await reopened.items()
        let stored = try XCTUnwrap(reopenedItems.first?.makerWorldSource)
        XCTAssertEqual(stored.pageURL, "https://makerworld.com/ko/models/1099461-sturdy-modular-filament-spool-rack-fully-printable")
        XCTAssertEqual(stored.profileURL, stored.pageURL + "#profileId-1791619")
        XCTAssertEqual(stored.plates?.first?.plateType, "Textured PEI Plate")
        let rawIndex = try String(contentsOf: repo.rootURL.appendingPathComponent("index.json"), encoding: .utf8)
        XCTAssertFalse(rawIndex.contains("secret"))
        XCTAssertFalse(rawIndex.contains("signature"))
        XCTAssertFalse(rawIndex.contains("private"))
    }

    func testLinkOnlySourcePreservesSnapshotButNewProfileClearsOldEstimates() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123-original",
            profileURL: "https://makerworld.com/en/models/123-original#profileId-456", capturedAt: oldDate,
            title: "모델", profileTitle: "첫 프로필", estimatedSeconds: 3600, plateCount: 1,
            plates: [WebPlateRecord(id: "1", estimatedSeconds: 3600)]))
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/123-renamed", capturedAt: newDate))
        var stored = await repo.items()[0].makerWorldSource
        XCTAssertEqual(stored?.capturedAt, oldDate)
        XCTAssertEqual(stored?.estimatedSeconds, 3600)
        XCTAssertEqual(stored?.profileTitle, "첫 프로필")
        XCTAssertEqual(stored?.pageURL, "https://makerworld.com/ko/models/123-renamed")
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/123-renamed",
            profileURL: "https://makerworld.com/ko/models/123-renamed#profileId-789", capturedAt: newDate))
        stored = await repo.items()[0].makerWorldSource
        XCTAssertEqual(stored?.capturedAt, newDate)
        XCTAssertEqual(stored?.title, "모델")
        XCTAssertNil(stored?.plates)
        XCTAssertNil(stored?.profileTitle)
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/123-renamed",
            profileURL: "https://makerworld.com/ko/models/123-renamed#profileId-789", capturedAt: newDate,
            plates: []))
        stored = await repo.items()[0].makerWorldSource
        XCTAssertEqual(stored?.plates, [])
        XCTAssertNil(stored?.estimatedSeconds)
    }

    func testSourceRejectsDownloadRoutesOtherHostsAndMismatchedModels() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        for bad in ["http://makerworld.com/en/models/123", "https://makerworld.com.evil.example/en/models/123", "https://makerworld.bblmw.com/model/file.3mf?token=secret", "https://makerworld.com/api/v1/download/123", "https://user:secret@makerworld.com/en/models/123", "https://makerworld.com/en/models/US123abc"] {
            do { try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: bad)); XCTFail("Accepted unsafe source") }
            catch LibraryError.invalidSource { }
        }
        do {
            try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", profileURL: "https://makerworld.com/en/models/456#profileId-789"))
            XCTFail("Accepted mismatched model")
        } catch LibraryError.invalidSource { }
        let stored = await repo.items()[0]
        XCTAssertNil(stored.makerWorldSource)
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123?printProfileId=456&token=private"))
        let valid = await repo.items()[0].makerWorldSource
        XCTAssertEqual(valid?.pageURL, "https://makerworld.com/en/models/123")
        XCTAssertEqual(valid?.profileURL, "https://makerworld.com/en/models/123#profileId-456")
    }

    func testLegacyIndexWithoutSourceDecodesAndNoURLIsGuessed() async throws {
        let repo = try repository()
        let imported = try await repo.importFile(at: fixture()).item
        XCTAssertNotNil(imported.modelID)
        XCTAssertNil(imported.makerWorldSource)
        let url = repo.rootURL.appendingPathComponent("index.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "makerWorldSource")
        json["items"] = items
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let old = await reopened.items()[0]
        XCTAssertNil(old.makerWorldSource)
        XCTAssertEqual(old.modelID, imported.modelID)
    }

    func testWebProfileTotalsDoNotInventIndividualPlateDetails() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/1099461",
            profileURL: "https://makerworld.com/ko/models/1099461#profileId-1791619",
            estimatedSeconds: 11.7 * 3600, plateCount: 7))
        var source = await repo.items()[0].makerWorldSource
        XCTAssertEqual(source?.estimatedSeconds, 42_120)
        XCTAssertEqual(source?.plateCount, 7)
        XCTAssertNil(source?.plates)
        XCTAssertNil(source?.knownPlateEstimatedSeconds)
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/1099461",
            profileURL: "https://makerworld.com/ko/models/1099461#profileId-1791619",
            plateCount: 7, plates: [WebPlateRecord(id: "1", estimatedSeconds: 1200, weightGrams: 20)]))
        source = await repo.items()[0].makerWorldSource
        XCTAssertEqual(source?.estimatedSeconds, 42_120)
        XCTAssertNil(source?.knownPlateEstimatedSeconds)
        XCTAssertNil(source?.weightGrams)
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/ko/models/1099461",
            profileURL: "https://makerworld.com/ko/models/1099461#profileId-1791619", plateCount: 3))
        source = await repo.items()[0].makerWorldSource
        XCTAssertEqual(source?.plateCount, 3)
        XCTAssertNil(source?.estimatedSeconds)
        XCTAssertNil(source?.plates)
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let reopenedItems = await reopened.items()
        XCTAssertEqual(reopenedItems[0].makerWorldSource?.plateCount, 3)
    }

    func testUnsafeSourceInStoredIndexIsPreservedAndRejected() async throws {
        let repo = try repository()
        let item = try await repo.importFile(at: fixture()).item
        try await repo.updateSource(id: item.id, source: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123"))
        let url = repo.rootURL.appendingPathComponent("index.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        var source = try XCTUnwrap(items[0]["makerWorldSource"] as? [String: Any])
        source["pageURL"] = "file:///etc/passwd"
        items[0]["makerWorldSource"] = source; json["items"] = items
        let malicious = try JSONSerialization.data(withJSONObject: json)
        try malicious.write(to: url)
        XCTAssertThrowsError(try LibraryRepository(rootURL: repo.rootURL))
        XCTAssertEqual(try Data(contentsOf: url), malicious)
    }

    func testExpectedHashMismatchNeverMutatesEmptyOrExistingLibrary() async throws {
        let repo = try repository()
        let file = try fixture()
        let original = try Data(contentsOf: file)
        let indexURL = repo.rootURL.appendingPathComponent("index.json")
        let mismatchedHash = String(repeating: "0", count: 64)
        do {
            _ = try await repo.importFile(at: file, expectedSHA256: mismatchedHash)
            XCTFail("Accepted mismatched expected hash")
        } catch LibraryError.invalidArchive { }
        let empty = await repo.items()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent("Files").path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent(".staging").path), [])
        XCTAssertEqual(try Data(contentsOf: file), original)

        let actualHash = try LibraryRepository.hashFile(file)
        let first = try await repo.importFile(at: file, expectedSHA256: actualHash.uppercased()).item
        let originalIndex = try Data(contentsOf: indexURL)
        let anotherPath = temp.appendingPathComponent("IdenticalOtherPath.3mf")
        try FileManager.default.copyItem(at: file, to: anotherPath)
        do {
            _ = try await repo.importFile(at: anotherPath, expectedSHA256: mismatchedHash)
            XCTFail("Updated duplicate provenance before checking hash")
        } catch LibraryError.invalidArchive { }
        let current = await repo.items()
        XCTAssertEqual(current, [first])
        XCTAssertEqual(try Data(contentsOf: indexURL), originalIndex)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try Data(contentsOf: anotherPath), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.rootURL.appendingPathComponent(".staging").path), [])
    }

    func testMalformedExpectedHashesAreRejectedBeforeImport() async throws {
        let repo = try repository()
        let file = try fixture()
        for value in ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "g", count: 64), "../../archive"] {
            do { _ = try await repo.importFile(at: file, expectedSHA256: value); XCTFail("Accepted malformed hash") }
            catch LibraryError.invalidArchive { }
        }
        let empty = await repo.items()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.rootURL.appendingPathComponent("index.json").path))
    }
}

extension LibraryRepositoryTests {
    func testFilamentSlotMappingAndBackfillPreserveLegacyPrintRecords() async throws {
        let settings = Data(##"{"filament_type":["PLA","PETG"],"filament_settings_id":["Bambu PLA Basic","Generic PETG"],"filament_colour":["#F5CF00","#FF0000"]}"##.utf8)
        let slices = Data(##"<config><plate><metadata key="index" value="2"/><filament id="2" type="PETG" color="#FF0000" used_g="3.5" used_m="1.2"/></plate><plate><metadata key="index" value="1"/><filament id="1" type="PLA" color="#F5CF00" used_g="12" used_m="4"/></plate></config>"##.utf8)
        let repo = try repository(), source = try fixture(changes: ["Metadata/project_settings.config": settings, "Metadata/slice_info.config": slices])
        let item = try await repo.importFile(at: source).item
        XCTAssertEqual(item.filaments?.map(\.name), ["Bambu PLA Basic", "Generic PETG"])
        XCTAssertEqual(item.plates[0].filaments?.first?.name, "Generic PETG")
        XCTAssertEqual(item.plates[0].filaments?.first?.grams, 3.5)
        XCTAssertEqual(item.plates[1].filaments?.first?.color, "#F5CF00")
        let run = PrintRun(status: "completed", source: "manual", note: "Keep this", durationSeconds: 1620, durationSource: "makerWorld", filaments: [FilamentRecord(material: "PLA", grams: 12)])
        try await repo.appendRun(itemID: item.id, run: run)
        // Simulate an older index without newly imported filament metadata.
        let indexURL = repo.rootURL.appendingPathComponent("index.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String:Any])
        var items = try XCTUnwrap(json["items"] as? [[String:Any]])
        items[0].removeValue(forKey: "filaments")
        var plates = items[0]["plates"] as! [[String:Any]]
        for i in plates.indices { plates[i].removeValue(forKey: "filaments") }
        items[0]["plates"] = plates; json["items"] = items
        try JSONSerialization.data(withJSONObject: json).write(to: indexURL)
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        try await reopened.recoverFilaments()
        let restored = await reopened.items()[0]
        XCTAssertEqual(restored.printRuns.count, 1); XCTAssertEqual(restored.printRuns[0].note, run.note); XCTAssertEqual(restored.printRuns[0].durationSeconds, run.durationSeconds); XCTAssertEqual(restored.printRuns[0].filaments, run.filaments); XCTAssertEqual(restored.filaments, item.filaments)
        XCTAssertEqual(restored.plates.map(\.filaments), item.plates.map(\.filaments))
        let bytes = try Data(contentsOf: indexURL); try await reopened.recoverFilaments()
        XCTAssertEqual(try Data(contentsOf: indexURL), bytes)
    }
    func testInvalidPrintDetailsAreRejectedBeforeFileMoves() async throws {
        let repo = try repository(), source = try fixture(), item = try await repo.importFile(at: source).item
        do { _ = try await repo.completePrint(itemID: item.id, note: "", durationSeconds: -1); XCTFail("Invalid duration") } catch {}
        do { try await repo.appendRun(itemID: item.id, run: PrintRun(status: "completed", source: "manual", filaments: [FilamentRecord(grams: -.infinity)])); XCTFail("Invalid filament") } catch {}
        let records = await repo.items(); XCTAssertTrue(records[0].printRuns.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.rootURL.appendingPathComponent(item.filePath).path))
    }
}
