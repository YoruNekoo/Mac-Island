import Foundation

/// Reads the Downloads directory and reports partial files. Safe to run off the main actor.
enum DownloadScanner {
    /// Chrome/Edge/Brave/Arc (.crdownload), Opera (.opdownload), Firefox (.part), Safari (.download package).
    static let partialExtensions: Set<String> = ["crdownload", "opdownload", "part", "download"]

    struct Partial: Equatable, Sendable {
        let id: String
        let displayName: String
        let bytes: Int64
    }

    struct Snapshot: Equatable, Sendable {
        var partials: [Partial] = []
        /// Names of every non-partial entry in the directory.
        var finalNames: Set<String> = []
        /// Modification dates of the non-partial entries listed in `watching`.
        var finalModified: [String: Date] = [:]
    }

    enum Outcome: Equatable, Sendable {
        case snapshot(Snapshot)
        /// macOS refused folder access. The monitor stays hidden and does not retry.
        case accessDenied
    }

    /// Runs on the global executor, never the main actor.
    @concurrent
    static func scan(directory: URL, watching: Set<String>) async -> Outcome {
        scanSynchronously(directory: directory, watching: watching)
    }

    static func scanSynchronously(directory: URL, watching: Set<String>) -> Outcome {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [])
        } catch {
            return isAccessDenied(error) ? .accessDenied : .snapshot(Snapshot())
        }

        var snapshot = Snapshot()
        for url in entries {
            let name = url.lastPathComponent
            guard partialExtensions.contains(url.pathExtension.lowercased()) else {
                snapshot.finalNames.insert(name)
                if watching.contains(name),
                   let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    snapshot.finalModified[name] = modified
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            // Safari's .download is a package (directory): sum its contents. Others are single files.
            let bytes = values?.isDirectory == true ? recursiveSize(of: url) : Int64(values?.fileSize ?? 0)
            snapshot.partials.append(Partial(id: name,
                                             displayName: url.deletingPathExtension().lastPathComponent,
                                             bytes: bytes))
        }
        return .snapshot(snapshot)
    }

    /// Current size of each named partial file or package, or nil if it is gone. Reads only those paths, never the
    /// whole folder, so sampling a growing download costs the same in a folder of 20,000 files as in an empty one.
    static func measure(directory: URL, partialNames: Set<String>) -> [String: Int64?] {
        var sizes: [String: Int64?] = [:]
        for name in partialNames {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else {
                sizes[name] = .some(nil)
                continue
            }
            sizes[name] = values.isDirectory == true ? recursiveSize(of: url) : Int64(values.fileSize ?? 0)
        }
        return sizes
    }

    static func recursiveSize(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func isAccessDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain { return nsError.code == NSFileReadNoPermissionError }
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code == Int(EPERM) || nsError.code == Int(EACCES) }
        return false
    }
}
