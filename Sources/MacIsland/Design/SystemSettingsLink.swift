import AppKit

/// Panes of System Settings that Mac Island sends people to. One list, one way to open them.
enum SystemSettingsLink {
    case automation
    case calendars
    /// Files & Folders, where the Downloads folder permission lives.
    case downloads

    private var urlString: String {
        switch self {
        case .automation: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .calendars: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .downloads: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        }
    }

    @MainActor
    func open() {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
