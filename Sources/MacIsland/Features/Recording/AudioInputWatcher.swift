import CoreAudio
import Foundation

/// Watches every audio device that has input streams and reports whether any of them is running
/// somewhere (some process is using it). Purely listener-driven; there is no timer.
///
/// All mutable state lives on `queue`. CoreAudio delivers listener callbacks on that same queue, and
/// `start`/`stop` run synchronously on it, so no callback can run concurrently or after `stop()` returns.
final class AudioInputWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macisland.audio-input-watcher")
    private let deviceFilter: @Sendable (AudioObjectID) -> Bool

    private var onChange: (@Sendable (Bool) -> Void)?
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var isStarted = false
    private var lastValue = false
    private var hasReported = false

    /// `deviceFilter` defaults to "has input streams". Tests may pass a different filter.
    init(deviceFilter: @escaping @Sendable (AudioObjectID) -> Bool = AudioInputWatcher.hasInputStreams) {
        self.deviceFilter = deviceFilter
    }

    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            self.onChange = onChange

            var address = Self.devicesAddress
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reconcileDevices() }
            deviceListListener = listener
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            reconcileDevices()
        }
    }

    func stop() {
        queue.sync {
            guard isStarted else { return }
            isStarted = false
            if let deviceListListener {
                var address = Self.devicesAddress
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, deviceListListener)
            }
            deviceListListener = nil
            for (id, block) in deviceListeners {
                var address = Self.runningAddress
                AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
            }
            deviceListeners.removeAll()
            onChange = nil
            lastValue = false
            hasReported = false
        }
    }

    /// Number of devices currently being listened to (for tests).
    var trackedDeviceCount: Int { queue.sync { deviceListeners.count } }

    // MARK: - On `queue`

    /// Adds listeners for new devices, removes them for devices that disappeared, then re-evaluates.
    private func reconcileDevices() {
        guard isStarted else { return }
        let current = Set(Self.allDevices().filter(deviceFilter))

        for id in Array(deviceListeners.keys) where !current.contains(id) {
            if let block = deviceListeners.removeValue(forKey: id) {
                var address = Self.runningAddress
                AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
            }
        }
        for id in current where deviceListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            var address = Self.runningAddress
            if AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr {
                deviceListeners[id] = block
            }
        }
        evaluate()
    }

    private func evaluate() {
        guard isStarted else { return }
        let value = deviceListeners.keys.contains { Self.isRunningSomewhere($0) }
        guard !hasReported || value != lastValue else { return }
        hasReported = true
        lastValue = value
        onChange?(value)
    }

    // MARK: - CoreAudio helpers

    private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static let runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    static func allDevices() -> [AudioObjectID] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    static func hasInputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    static func isRunningSomewhere(_ id: AudioObjectID) -> Bool {
        var address = runningAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }
}
