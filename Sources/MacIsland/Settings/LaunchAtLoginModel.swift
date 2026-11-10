import Observation
import ServiceManagement

/// The slice of `SMAppService` this needs, so the model can be tested without touching the real login items.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Launch at login, always mirroring the real `SMAppService` status (never a stored value).
@MainActor
@Observable
final class LaunchAtLoginModel {
    enum State: Equatable {
        case off
        case on
        /// Registered, but the user still has to allow it in System Settings > Login Items.
        case requiresApproval
        /// macOS cannot find the app as a login item (for example an unsigned build outside /Applications).
        case unavailable
    }

    private(set) var state: State
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
        state = Self.state(for: service.status)
    }

    static func state(for status: SMAppService.Status) -> State {
        switch status {
        case .enabled: .on
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        case .notRegistered: .off
        @unknown default: .off
        }
    }

    /// What the toggle shows: registered counts as on, even while approval is pending.
    var isOn: Bool { state == .on || state == .requiresApproval }

    /// Re-reads the real status. Call whenever Settings opens or the app becomes active.
    func refresh() {
        state = Self.state(for: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = enabled ? "Couldn't turn on Launch at login." : "Couldn't turn off Launch at login."
        }
        refresh()      // the toggle always ends up matching reality, so a failure reverts it
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
