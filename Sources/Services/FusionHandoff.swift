import AppKit
import CryptoKit
import PlateShelfCore

struct FusionMesh: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
}
struct FusionSelection: Identifiable {
    let id = UUID()
    let title: String
    let meshes: [FusionMesh]
}

enum FusionHandoff {
    static let bundleIdentifier = "com.autodesk.fusion360"

    // Autodesk's documented handler opens an independent design. 3MF is not a
    // documented handler input; Studio exports STL so Fusion can import a mesh.
    static func openURL(for mesh: URL) throws -> URL {
        guard mesh.isFileURL, mesh.pathExtension.lowercased() == "stl",
              let encoded = mesh.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "fusion360://host/?command=open&file=" + encoded) else {
            throw ShelfError.message(L("fusion.invalidMesh"))
        }
        return url
    }

    @MainActor static func applicationURL() -> URL? {
        let workspace = NSWorkspace.shared
        var candidates = workspace.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }.compactMap(\.bundleURL)
        if let registered = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) { candidates.append(registered) }
        candidates.append(URL(fileURLWithPath: "/Applications/Autodesk Fusion.app"))
        // The Applications entry can be Autodesk's launcher, not the real app.
        // Resolve webdeploy without pinning the changing version directory.
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Autodesk/webdeploy/production")
        let deployments = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .prefix(128).map { $0.appendingPathComponent("Autodesk Fusion.app") }
            .filter { Bundle(url: $0)?.bundleIdentifier == bundleIdentifier }
            .sorted {
                let a = Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                let b = Bundle(url: $1)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                return a.compare(b, options: .numeric) == .orderedDescending
            }
        candidates.append(contentsOf: deployments)
        return candidates.first { Bundle(url: $0)?.bundleIdentifier == bundleIdentifier }
    }
}

actor FusionMeshExporter {
    private nonisolated let slot = StudioProcessSlot()
    nonisolated func stop() { slot.stop() }
    private let maxMeshBytes = 512 * 1_024 * 1_024
    private struct CachedFile: Codable, Equatable { let name: String; let hash: String }

    func export(input: URL, studio: URL, cacheRoot: URL) async throws -> [FusionMesh] {
        guard let bundle = Bundle(url: studio), bundle.bundleIdentifier == "com.bambulab.bambu-studio",
              let executable = bundle.executableURL else { throw ShelfError.message(L("fusion.studioMissing")) }
        let fm = FileManager.default
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 4 * 1_024 * 1_024 * 1_024 else {
            throw ShelfError.message(L("fusion.invalidMesh"))
        }
        // Hash actual archived bytes, so replacement files never reuse stale meshes.
        let sourceHash = try Self.hashFile(input)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let key = SHA256.hash(data: Data("Fusion-mesh-v1\n\(sourceHash)\n\(version)".utf8)).map { String(format: "%02x", $0) }.joined()
        let cache = cacheRoot.appendingPathComponent(key)
        if let existing = try? meshes(in: cache), !existing.isEmpty,
           let manifest = try? Data(contentsOf: cache.appendingPathComponent("manifest.json")), manifest.count < 1_048_576,
           let saved = try? JSONDecoder().decode([CachedFile].self, from: manifest),
           let actual = try? existing.map({ CachedFile(name: $0.url.lastPathComponent, hash: try Self.hashFile($0.url)) }),
           actual == saved { return existing }

        let temporary = fm.temporaryDirectory.appendingPathComponent("MakerDock-Fusion-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary.appendingPathComponent("settings"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let copy = temporary.appendingPathComponent("model.3mf")
        try fm.copyItem(at: input, to: copy)
        guard try Self.hashFile(copy) == sourceHash else { throw ShelfError.message(L("fusion.sourceChanged")) }
        let output = temporary.appendingPathComponent("export")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = temporary
        process.arguments = Self.arguments(input: copy, output: output, settings: temporary.appendingPathComponent("settings"))
        let logURL = temporary.appendingPathComponent("export.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        process.standardOutput = log; process.standardError = log; process.standardInput = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run(); slot.set(process)
        defer { slot.set(nil) }
        let deadline = Date().addingTimeInterval(180)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw ShelfError.message(L("fusion.timeout")) }
                let logSize = (try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard logSize < 8 * 1_024 * 1_024 else { throw ShelfError.message(L("fusion.exportFailed")) }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw error
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw ShelfError.message(L("fusion.exportFailed")) }
        let exported = try meshes(in: output.appendingPathComponent("stl"))
        guard !exported.isEmpty else { throw ShelfError.message(L("fusion.noGeometry")) }
        let prepared = temporary.appendingPathComponent("prepared")
        try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
        for mesh in exported {
            let target = prepared.appendingPathComponent(mesh.url.lastPathComponent)
            try fm.copyItem(at: mesh.url, to: target)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
        }
        let manifest = try exported.map { CachedFile(name: $0.url.lastPathComponent, hash: try Self.hashFile($0.url)) }
        try JSONEncoder().encode(manifest).write(to: prepared.appendingPathComponent("manifest.json"), options: .atomic)
        try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        // Only generated meshes live here. Original archives and Studio working
        // copies are never overwritten or handed to Fusion for editing.
        if fm.fileExists(atPath: cache.path) { try fm.removeItem(at: cache) }
        try fm.moveItem(at: prepared, to: cache)
        return try meshes(in: cache)
    }

    static func arguments(input: URL, output: URL, settings: URL) -> [String] {
        ["--datadir", settings.path, "--debug", "1", "--export-stl", "--outputdir", output.path, input.path]
    }

    func meshes(in directory: URL) throws -> [FusionMesh] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw ShelfError.message(L("fusion.invalidMesh")) }
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            .filter { $0.pathExtension.lowercased() == "stl" }
        guard files.count <= 256 else { throw ShelfError.message(L("fusion.tooLarge")) }
        var total = 0
        for file in files {
            let value = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard value.isRegularFile == true, value.isSymbolicLink != true,
                  let size = value.fileSize, size >= 134, size <= maxMeshBytes - total else { throw ShelfError.message(L("fusion.invalidMesh")) }
            total += size
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 84) ?? Data()
            guard header.count == 84 else { throw ShelfError.message(L("fusion.invalidMesh")) }
            let triangles = header[80..<84].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            guard triangles > 0, UInt64(size) == 84 + UInt64(triangles) * 50 else { throw ShelfError.message(L("fusion.invalidMesh")) }
        }
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { FusionMesh(url: $0) }
    }

    private static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor extension LibraryViewModel {
    func openInFusion(_ item: ShelfItem) {
        guard fusionOpeningID == nil, !isWorking, !item.isTrashed else { return }
        guard FusionHandoff.applicationURL() != nil else { errorMessage = L("fusion.missing"); return }
        fusionOpeningID = item.id
        statusMessage = L("fusion.preparing")
        let input = fileURL(item), studio = URL(fileURLWithPath: preferences.studioPath)
        fusionTask = Task {
            defer { fusionOpeningID = nil; fusionTask = nil }
            do {
                let meshes = try await fusionExporter.export(input: input, studio: studio, cacheRoot: rootURL.appendingPathComponent("FusionExports"))
                try Task.checkCancellation()
                if meshes.count == 1 { sendToFusion(meshes[0]) }
                else { fusionSelection = FusionSelection(title: item.title, meshes: meshes); statusMessage = L("fusion.choose") }
            } catch is CancellationError { statusMessage = "" }
            catch { statusMessage = ""; errorMessage = error.localizedDescription }
        }
    }
    func sendToFusion(_ mesh: FusionMesh) {
        do {
            guard let app = FusionHandoff.applicationURL() else { throw ShelfError.message(L("fusion.missing")) }
            let url = try FusionHandoff.openURL(for: mesh.url)
            let config = NSWorkspace.OpenConfiguration(); config.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config) { [weak self] _, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription }
                    else { self?.statusMessage = L("fusion.sent") }
                }
            }
            fusionSelection = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
