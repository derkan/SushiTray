import Foundation

enum SushiBinary {
    /// Homebrew + common bins — GUI apps often lack these on PATH.
    private static let brewBinPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    private static let lock = NSLock()
    private static var whichCache: [String: String?] = [:]

    /// Absolute path to `sushi` on PATH (incl. Homebrew), if present.
    static func resolve() -> String? {
        resolve(fromCommandToken: "sushi")
    }

    /// Resolves the binary from the first command token (cached per token).
    static func resolve(fromCommandToken token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("/") {
            let path = PathExpanding.normalize(trimmed)
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }

        lock.lock()
        if let cached = whichCache[trimmed] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = lookup(trimmed)
        lock.lock()
        whichCache[trimmed] = resolved
        lock.unlock()
        return resolved
    }

    static func isAvailable(command: String) -> Bool {
        let tokens = CommandTokenizer.tokenize(command)
        guard let first = tokens.first else { return resolve() != nil }
        return resolve(fromCommandToken: first) != nil
    }

    /// Clears the lookup cache (e.g. after brew install).
    static func clearCache() {
        lock.lock()
        whichCache.removeAll()
        lock.unlock()
    }

    private static func lookup(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in brewBinPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return which(name)
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        let prefix = brewBinPaths.joined(separator: ":") + ":/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = env["PATH"], !existing.isEmpty {
            env["PATH"] = prefix + ":" + existing
        } else {
            env["PATH"] = prefix
        }
        process.environment = env
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}
