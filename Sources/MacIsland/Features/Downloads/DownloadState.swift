import Foundation

/// One browser download, inferred from its partial file. Progress is heuristic: only the growing size is
/// known, never a percentage or time estimate.
struct DownloadItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case downloading
        case completed
    }

    /// Stable key: the partial file's name, e.g. "movie.mp4.crdownload".
    let id: String
    var displayName: String
    var bytes: Int64
    var state: State
    /// Order in which downloads were first seen (higher is newer).
    let sequence: Int
    /// Whether a finished file with the final name already existed when the partial first appeared.
    let finalExistedAtStart: Bool
    let firstSeen: Date
}

enum DownloadFormatting {
    /// "420 MB". An empty partial file reads "Starting…".
    static func size(_ bytes: Int64) -> String {
        bytes <= 0 ? "Starting…" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
