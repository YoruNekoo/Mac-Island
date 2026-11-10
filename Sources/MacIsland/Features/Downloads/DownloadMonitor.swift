import Dispatch
import Foundation
import Observation

/// Heuristic browser-download tracker. It infers downloads from partial files in ~/Downloads, so it
/// knows a name and a growing size, never a percentage or an estimate.
///
/// - FSEvents wakes it when files appear or disappear.
/// - A 1 s size sampler runs only while at least one partial file exists; otherwise there is no timer.
/// - A completion is shown only if the final file really appears. A cancelled download clears silently.
@MainActor
@Observable
final class DownloadMonitor {
    private(set) var items: [DownloadItem] = []
    /// False once macOS has denied access to the folder. The feature then stays hidden.
    private(set) var isAvailable = true

    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let watcher = DirectoryEventWatcher()
    @ObservationIgnored private var tracked: [String: DownloadItem] = [:]
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var rescanQueued = false
    @ObservationIgnored private var isStarted = false

    /// Called when a download really finished (its final file appeared), never for a cancelled one.
    @ObservationIgnored var onCompletion: (@MainActor () -> Void)?

    static let sampleInterval: Duration = .seconds(1)
    static let completionDisplayTime: Duration = .seconds(5)

    init(directory: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first) {
        self.directory = directory
    }

    // MARK: - What the UI shows

    var isSampling: Bool { samplingTask != nil }
    var isRunning: Bool { isStarted }

    /// Newest in-progress download; otherwise the newest completed one.
    var primary: DownloadItem? {
        let downloading = items.filter { $0.state == .downloading }
        return (downloading.isEmpty ? items : downloading).max { $0.sequence < $1.sequence }
    }

    /// Other in-progress downloads, for the "+N more" label.
    var moreCount: Int {
        guard primary?.state == .downloading else { return 0 }
        return items.filter { $0.state == .downloading }.count - 1
    }

    /// Fixed items for rendering previews and layout checks. Starts nothing.
    static func preview(items: [DownloadItem], isAvailable: Bool = true) -> DownloadMonitor {
        let monitor = DownloadMonitor(directory: nil)
        monitor.items = items
        monitor.isAvailable = isAvailable
        return monitor
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted, let directory else { return }
        isStarted = true
        isAvailable = true     // an explicit (re-)enable gets a fresh attempt; macOS itself never re-prompts after a denial
        watcher.start(path: directory.path, structuralOnly: true) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.requestRescan() } }
        }
        requestRescan()
    }

    func stop() {
        isStarted = false
        watcher.stop()
        samplingTask?.cancel()
        samplingTask = nil
        expiryTasks.values.forEach { $0.cancel() }
        expiryTasks.removeAll()
        tracked.removeAll()
        publish()
    }

    // MARK: - Scanning

    /// Coalesces overlapping requests: a scan already in flight just runs once more when it finishes.
    func requestRescan() {
        guard isStarted, isAvailable, directory != nil else { return }
        if isScanning {
            rescanQueued = true
            return
        }
        isScanning = true
        Task { await runScans() }
    }

    private func runScans() async {
        guard let directory else { return }
        repeat {
            rescanQueued = false
            let watching = Set(tracked.values.filter { $0.state == .downloading }.map(\.displayName))
            let outcome = await DownloadScanner.scan(directory: directory, watching: watching)
            guard isStarted else { break }
            switch outcome {
            case .accessDenied:
                isAvailable = false           // fail quietly; never retried, so never re-prompts
                tracked.removeAll()
                publish()
            case .snapshot(let snapshot):
                apply(snapshot, now: Date())
            }
        } while rescanQueued && isAvailable
        isScanning = false
        updateSampling()
    }

    func apply(_ snapshot: DownloadScanner.Snapshot, now: Date) {
        var seen = Set<String>()
        for partial in snapshot.partials {
            seen.insert(partial.id)
            if var existing = tracked[partial.id], existing.state == .downloading {
                existing.bytes = partial.bytes
                tracked[partial.id] = existing
            } else {
                // New download (or a finished one reappearing): start fresh.
                expiryTasks[partial.id]?.cancel()
                expiryTasks[partial.id] = nil
                nextSequence += 1
                tracked[partial.id] = DownloadItem(
                    id: partial.id, displayName: partial.displayName, bytes: partial.bytes, state: .downloading,
                    sequence: nextSequence, finalExistedAtStart: snapshot.finalNames.contains(partial.displayName),
                    firstSeen: now)
            }
        }

        for item in tracked.values where item.state == .downloading && !seen.contains(item.id) {
            if didFinish(item, snapshot: snapshot) {
                var done = item
                done.state = .completed
                tracked[item.id] = done
                scheduleExpiry(of: item.id)
                onCompletion?()
            } else {
                tracked[item.id] = nil        // cancelled or failed: clear silently, never a completion
            }
        }
        publish()
    }

    /// The partial file vanished. It finished only if a file with the final name now exists and is not
    /// merely a leftover from before: either it did not exist when we first saw the partial, or it was
    /// modified since then.
    private func didFinish(_ item: DownloadItem, snapshot: DownloadScanner.Snapshot) -> Bool {
        guard snapshot.finalNames.contains(item.displayName) else { return false }
        if !item.finalExistedAtStart { return true }
        guard let modified = snapshot.finalModified[item.displayName] else { return false }
        return modified >= item.firstSeen.addingTimeInterval(-5)
    }

    private func scheduleExpiry(of id: String) {
        expiryTasks[id]?.cancel()
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.completionDisplayTime)
            guard !Task.isCancelled, let self else { return }
            if self.tracked[id]?.state == .completed {
                self.tracked[id] = nil
                self.publish()
            }
            self.expiryTasks[id] = nil
        }
    }

    // MARK: - Sampling (only while a partial file exists)

    private func updateSampling() {
        let needsSampling = isStarted && isAvailable && tracked.values.contains { $0.state == .downloading }
        if needsSampling, samplingTask == nil {
            samplingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.sampleInterval)
                    guard !Task.isCancelled, let self else { return }
                    await self.sampleSizes()
                    if !self.tracked.values.contains(where: { $0.state == .downloading }) { break }
                }
                self?.samplingTask = nil
            }
        } else if !needsSampling {
            samplingTask?.cancel()
            samplingTask = nil
        }
    }

    /// One sample of the growing partial files: reads only those paths (not the folder), so its cost does not
    /// depend on how many files the folder holds. A partial that vanished means the set of files changed, which
    /// is what the full scan is for.
    private func sampleSizes() async {
        guard isStarted, isAvailable, let directory, !isScanning else { return }
        let names = Set(tracked.values.filter { $0.state == .downloading }.map(\.id))
        guard !names.isEmpty else { return }
        let sizes = await Task.detached(priority: .utility) { DownloadScanner.measure(directory: directory, partialNames: names) }.value
        guard isStarted else { return }
        var vanished = false
        for (name, size) in sizes {
            guard var item = tracked[name], item.state == .downloading else { continue }
            if let size { item.bytes = size; tracked[name] = item } else { vanished = true }
        }
        if vanished { requestRescan() } else { publish(force: false) }
    }

    /// Item changes that are not just a growing byte count publish at once. A byte-only change publishes at most
    /// once per `minimumBytePublishInterval`, so the views redraw about once a second however often files change.
    static let minimumBytePublishInterval: Duration = .milliseconds(900)
    @ObservationIgnored private var lastPublish: ContinuousClock.Instant?

    private func publish(force: Bool = true) {
        let sorted = tracked.values.sorted { $0.sequence > $1.sequence }
        guard sorted != items else { return }
        let now = ContinuousClock.now
        if !force, sorted.count == items.count,
           zip(sorted, items).allSatisfy({ $0.id == $1.id && $0.state == $1.state }),
           let lastPublish, now - lastPublish < Self.minimumBytePublishInterval { return }
        items = sorted
        lastPublish = now
    }
}
