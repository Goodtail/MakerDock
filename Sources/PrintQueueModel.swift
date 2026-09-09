import Foundation
import PlateShelfCore

extension LibraryViewModel {
    func isQueued(_ item: ShelfItem) -> Bool { printQueue.contains { $0.id == item.id } }
    var queuedItems: [ShelfItem] {
        let models = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return printQueue.compactMap { models[$0.id] }
    }
    func queueSeconds(_ item: ShelfItem) -> Double? {
        printQueue.first { $0.id == item.id }?.durationSeconds ?? displayedEstimate(item)?.seconds
    }
    var queueJobs: [PrintQueueJob] { queuedItems.map { PrintQueueJob(id: $0.id, seconds: queueSeconds($0)) } }
    @discardableResult func enqueue(_ selected: [ShelfItem]) async -> Int {
        guard let repository else { return 0 }
        await acquireWork(); defer { releaseWork() }
        do {
            let count = try await repository.enqueue(itemIDs: selected.map(\.id))
            await reload()
            statusMessage = String(format: L("queue.added"), count)
            return count
        } catch { errorMessage = error.localizedDescription; return 0 }
    }
    func reorderQueue(_ ids: [String]) async {
        guard let repository else { return }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.reorderQueue(itemIDs: ids); await reload() }
        catch { errorMessage = error.localizedDescription }
    }
    func moveQueueItem(_ id: String, by delta: Int) async {
        var ids = printQueue.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return }
        ids.swapAt(index, index + delta); await reorderQueue(ids)
    }
    func removeQueueItem(_ id: String) async {
        guard let repository else { return }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.removeFromQueue(itemIDs: [id]); await reload() }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func setQueueDuration(_ id: String, seconds: Double?) async -> Bool {
        guard let repository else { return false }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.setQueueDuration(itemID: id, seconds: seconds); await reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
