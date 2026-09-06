import Foundation
import CryptoKit
import PlateShelfCore

extension LibraryViewModel {
    func scanStudioInbox(duringRefresh: Bool = false) async {
        guard let repository, !preferences.archivePath.isEmpty, (!isBusy || duringRefresh), !isReadingInbox else { return }
        isReadingInbox = true; defer { isReadingInbox = false }
        let inbox = URL(fileURLWithPath: preferences.archivePath).resolvingSymlinksInPath()
        guard let folders = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { archiveStatus = L("inbox.waiting"); return }
        var seen = 0, failures: [String] = []
        for folder in folders {
            guard let folderValues = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), folderValues.isDirectory == true, folderValues.isSymbolicLink != true,
                  folder.resolvingSymlinksInPath().deletingLastPathComponent() == inbox else { continue }
            let manifest = folder.appendingPathComponent("manifest.json")
            guard let values = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size < 1_000_000,
                  let data = try? Data(contentsOf: manifest) else { continue }
            let sig = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if archiveSignatures[folder.path] == sig { seen += 1; continue }
            do {
                let event = try JSONDecoder().decode(StudioEvent.self, from: data)
                guard event.schema_version == 1, event.event_type == "studio_submission", UUID(uuidString: event.event_id) != nil,
                      let artifact = event.artifacts.first(where: { $0.role == "gcode_3mf" }), artifact.relative_path == "print.3mf" else { continue }
                guard ["prepared", "submitted", "submission_failed", "canceled", "interrupted"].contains(event.submission_state) else {
                    throw ShelfError.message(L("inbox.invalidState"))
                }
                let url = folder.appendingPathComponent(artifact.relative_path)
                guard let fileValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), fileValues.isRegularFile == true, fileValues.isSymbolicLink != true, let fileSize = fileValues.fileSize, fileSize > 0, fileSize <= 4_294_967_296,
                      artifact.byte_count == nil || artifact.byte_count == fileSize,
                      url.resolvingSymlinksInPath().deletingLastPathComponent() == folder.resolvingSymlinksInPath() else { throw ShelfError.message(L("inbox.invalidArtifact")) }
                // Validate the manifest BEFORE ingestion, so a mismatch is never added to the library.
                let expectedHash = artifact.sha256
                let actualHash = try await Task.detached(priority: .utility) { () -> String in
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    var hasher = SHA256()
                    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
                    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
                }.value
                guard actualHash == expectedHash.lowercased() else { throw ShelfError.message(L("inbox.hashMismatch")) }
                let result = try await repository.importFile(at: url, expectedSHA256: expectedHash)
                let formatter = ISO8601DateFormatter()
                let date = formatter.date(from: event.created_at) ?? result.item.importedAt
                try await repository.appendRun(itemID: result.item.id, run: PrintRun(id: event.event_id, date: date, status: event.submission_state, source: "bambu_studio_patch", note: event.project_name))
                archiveSignatures[folder.path] = sig; seen += 1
            } catch { failures.append(error.localizedDescription) }
        }
        archiveStatus = seen > 0 ? String(format: L("inbox.count"), seen) : L("inbox.waiting")
        if !failures.isEmpty { archiveStatus += "\n" + L("inbox.error") + " " + failures.prefix(3).joined(separator: "\n") }
        if seen > 0 { await reload() }
    }
}
private struct StudioEvent: Decodable {
    let schema_version: Int, event_type: String, event_id: String, created_at: String, submission_state: String, project_name: String
    let artifacts: [StudioArtifact]
}
private struct StudioArtifact: Decodable { let role: String, relative_path: String, sha256: String; let byte_count: Int? }
