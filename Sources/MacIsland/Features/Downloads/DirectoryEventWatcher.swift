import CoreServices
import Foundation

/// Reports file-system changes under one directory using FSEvents. Callbacks run on a private serial
/// queue; after `stop()` returns, the handler can never be called again.
final class DirectoryEventWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macisland.directory-events")
    private var stream: FSEventStreamRef?
    private var handler: (@Sendable () -> Void)?
    private var structuralOnly = false

    /// Coalescing window for bursts of events (a growing download writes constantly).
    static let latency: CFTimeInterval = 0.3

    /// Flags that mean the *set* of files changed (something appeared, vanished or was renamed), as opposed to a
    /// file merely growing or being touched.
    static let structuralFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        | kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)

    /// With `structuralOnly`, a batch of events that only modified existing files (a download growing) does not
    /// call `handler`; callers that need sizes sample them directly.
    func start(path: String, structuralOnly: Bool = false, handler: @escaping @Sendable () -> Void) {
        queue.sync {
            guard stream == nil else { return }
            self.handler = handler
            self.structuralOnly = structuralOnly

            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<DirectoryEventWatcher>.fromOpaque(info).takeUnretainedValue()
                if watcher.structuralOnly {
                    let isStructural = (0..<count).contains { flags[$0] & DirectoryEventWatcher.structuralFlags != 0 }
                    guard isStructural else { return }
                }
                watcher.handler?()
            }
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [path] as CFArray,
                                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                    Self.latency, flags) else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            handler = nil
        }
    }
}
