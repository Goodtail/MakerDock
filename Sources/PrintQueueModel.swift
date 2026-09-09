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
    func queueEntry(_ item: ShelfItem) -> PrintQueueEntry? { printQueue.first { $0.id == item.id } }
    var activePrint: PrintQueueEntry? { printQueue.first(where: \.isPrinting) }
    var queueJobs: [PrintQueueJob] { queueJobs(at: Date()) }
    func queueJobs(at now: Date) -> [PrintQueueJob] {
        queuedItems.map { item in
            PrintQueueJob(id: item.id, seconds: remainingQueueSeconds(item, at: now))
        }
    }
    func remainingQueueSeconds(_ item: ShelfItem, at now: Date) -> Double? {
        if printerMonitor.ownsLiveJob(itemID: item.id) { return printerMonitor.remaining(itemID: item.id, at: now) }
        return queueEntry(item)?.remainingSeconds(at: now, estimate: displayedEstimate(item)?.seconds)
    }
    @discardableResult func bindPrinterJob(_ item: ShelfItem, startedAt: Date) async -> Bool {
        guard printerMonitor.snapshot.fresh(at: Date()), printerMonitor.session?.recorded == false,
              activePrint == nil || activePrint?.id == item.id else { return false }
        guard await startQueuePrint(item, at: startedAt) else { return false }
        do { try printerMonitor.bind(itemID: item.id, startedAt: startedAt); return true }
        catch { errorMessage = (error as? PrinterConnectionError)?.message ?? error.localizedDescription; return false }
    }
    func fittingQueueOrder(at now: Date, budget: Double, gap: Double) -> [String] {
        let jobs = queueJobs(at: now)
        guard let active = activePrint else {
            return PrintQueuePlan.fittingOrder(jobs: jobs, availableSeconds: budget, changeoverSeconds: gap)
        }
        guard let remaining = jobs.first?.seconds, remaining + gap <= budget else { return printQueue.map(\.id) }
        return [active.id] + PrintQueuePlan.fittingOrder(jobs: Array(jobs.dropFirst()), availableSeconds: budget - remaining - gap, changeoverSeconds: gap)
    }
    @discardableResult func startQueuePrint(_ item: ShelfItem, at date: Date) async -> Bool {
        guard let repository else { return false }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.startQueuePrint(itemID: item.id, at: date, estimatedSeconds: queueSeconds(item)); await reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func returnQueuePrintToWaiting(_ item: ShelfItem) async {
        guard let repository else { return }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.returnQueuePrintToWaiting(itemID: item.id); printerMonitor.unbind(itemID: item.id); await reload() }
        catch { errorMessage = error.localizedDescription }
    }

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
        do { try await repository.removeFromQueue(itemIDs: [id]); printerMonitor.unbind(itemID: id); await reload() }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func setQueueDuration(_ id: String, seconds: Double?) async -> Bool {
        guard let repository else { return false }
        await acquireWork(); defer { releaseWork() }
        do { try await repository.setQueueDuration(itemID: id, seconds: seconds); await reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
