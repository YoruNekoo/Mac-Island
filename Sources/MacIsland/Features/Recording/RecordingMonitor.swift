import Dispatch
import Observation

/// Publishes whether any microphone or camera is in use by *some* process. It cannot say which app:
/// no public API exposes that. Both inputs are listener-driven (CoreAudio / CoreMediaIO); nothing polls.
@MainActor
@Observable
final class RecordingMonitor {
    private(set) var isMicrophoneInUse = false
    private(set) var isCameraInUse = false

    @ObservationIgnored private let audio: AudioInputWatcher
    @ObservationIgnored private let camera: CameraWatcher

    var isAnyActive: Bool { isMicrophoneInUse || isCameraInUse }
    private(set) var isRunning = false

    init(audio: AudioInputWatcher = AudioInputWatcher(), camera: CameraWatcher = CameraWatcher()) {
        self.audio = audio
        self.camera = camera
    }

    /// Fixed state for rendering previews and layout checks. Starts no listeners.
    static func preview(microphone: Bool, camera: Bool) -> RecordingMonitor {
        let monitor = RecordingMonitor()
        monitor.isMicrophoneInUse = microphone
        monitor.isCameraInUse = camera
        return monitor
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Watcher callbacks arrive on their own serial queues. Hop to the main queue (which keeps order),
        // then assert main-actor isolation to publish.
        audio.start { [weak self] inUse in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.isMicrophoneInUse = inUse } }
        }
        camera.start { [weak self] inUse in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.isCameraInUse = inUse } }
        }
    }

    func stop() {
        isRunning = false
        audio.stop()
        camera.stop()
        isMicrophoneInUse = false
        isCameraInUse = false
    }
}
