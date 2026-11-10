import Foundation

enum AppleScriptError: Error, Equatable, Sendable {
    case notAuthorized            // -1743: user denied (or has not allowed) Automation
    case appNotRunning
    case failed(code: Int, message: String)
}

/// Runs AppleScript on a single serial executor. `NSAppleScript` is not thread-safe, so every
/// instance is created and used inside this actor, and only Sendable values leave it.
actor AppleScriptRunner {
    /// Reads (snapshot, timing, artwork).
    static let shared = AppleScriptRunner(priority: .read)
    /// Play/pause, next, previous and seek. A separate actor with higher priority: a command never waits behind
    /// a backlog of reads, only for the single script that is already running.
    static let commands = AppleScriptRunner(priority: .command)

    private let priority: ScriptPriority

    init(priority: ScriptPriority = .read) {
        self.priority = priority
    }

    func runForString(_ source: String) async throws -> String? {
        try await serialized { try self.execute(source).stringValue }
    }

    /// Runs a script that returns a list of numbers, e.g. `{12.5, 240}`. An empty list gives `[]`.
    func runForNumbers(_ source: String) async throws -> [Double] {
        try await serialized {
            let descriptor = try self.execute(source)
            let count = descriptor.numberOfItems
            guard count > 0 else { return [] }
            return (1...count).compactMap { descriptor.atIndex($0)?.doubleValue }
        }
    }

    func runForData(_ source: String) async throws -> Data? {
        try await serialized {
            let data = try self.execute(source).data
            return data.isEmpty ? nil : data
        }
    }

    /// `NSAppleScript` is not documented as safe to run concurrently, so only one script ever executes at a time,
    /// process-wide. Commands are admitted ahead of waiting reads.
    private func serialized<T>(_ work: () throws -> T) async throws -> T {
        await ScriptGate.shared.acquire(priority)
        let result = Result { try work() }
        await ScriptGate.shared.release()
        return try result.get()
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.failed(code: 0, message: "Script could not be compiled")
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo["NSAppleScriptErrorNumber"] as? Int ?? 0
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            switch code {
            case -1743: throw AppleScriptError.notAuthorized
            case -600: throw AppleScriptError.appNotRunning
            default: throw AppleScriptError.failed(code: code, message: message)
            }
        }
        return result
    }
}

enum ScriptPriority: Sendable {
    case command, read
}

/// Admits one script at a time. Waiting commands go before waiting reads; within a priority it is first come,
/// first served.
actor ScriptGate {
    static let shared = ScriptGate()

    private var isBusy = false
    private var commandWaiters: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [CheckedContinuation<Void, Never>] = []

    func acquire(_ priority: ScriptPriority) async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            switch priority {
            case .command: commandWaiters.append(continuation)
            case .read: readWaiters.append(continuation)
            }
        }
    }

    func release() {
        if !commandWaiters.isEmpty {
            commandWaiters.removeFirst().resume()
        } else if !readWaiters.isEmpty {
            readWaiters.removeFirst().resume()
        } else {
            isBusy = false
        }
    }
}
