import CoreMediaIO
import Foundation

/// Watches every CoreMediaIO device (cameras, including virtual ones) and reports whether any is
/// running somewhere. Same threading model as `AudioInputWatcher`: all state on one serial queue,
/// listener-driven, no timer.
final class CameraWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macisland.camera-watcher")

    private var onChange: (@Sendable (Bool) -> Void)?
    private var deviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var deviceListListener: CMIOObjectPropertyListenerBlock?
    private var isStarted = false
    private var lastValue = false
    private var hasReported = false

    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            self.onChange = onChange

            var address = Self.devicesAddress
            let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.reconcileDevices() }
            deviceListListener = listener
            CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, listener)
            reconcileDevices()
        }
    }

    func stop() {
        queue.sync {
            guard isStarted else { return }
            isStarted = false
            if let deviceListListener {
                var address = Self.devicesAddress
                CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, deviceListListener)
            }
            deviceListListener = nil
            for (id, block) in deviceListeners {
                var address = Self.runningAddress
                CMIOObjectRemovePropertyListenerBlock(id, &address, queue, block)
            }
            deviceListeners.removeAll()
            onChange = nil
            lastValue = false
            hasReported = false
        }
    }

    var trackedDeviceCount: Int { queue.sync { deviceListeners.count } }

    // MARK: - On `queue`

    private func reconcileDevices() {
        guard isStarted else { return }
        let current = Set(Self.allDevices())

        for id in Array(deviceListeners.keys) where !current.contains(id) {
            if let block = deviceListeners.removeValue(forKey: id) {
                var address = Self.runningAddress
                CMIOObjectRemovePropertyListenerBlock(id, &address, queue, block)
            }
        }
        for id in current where deviceListeners[id] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            var address = Self.runningAddress
            if CMIOObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr {
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

    // MARK: - CoreMediaIO helpers

    private static let devicesAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    private static let runningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    static func allDevices() -> [CMIOObjectID] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr
        else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func isRunningSomewhere(_ id: CMIOObjectID) -> Bool {
        var address = runningAddress
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
            && value != 0
    }
}
