import Foundation

enum SushiBinary {
    /// Absolute path to `sushi` on PATH, if present.
    static func resolve() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["sushi"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
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

    /// Resolves the binary from the first command token.
    static func resolve(fromCommandToken token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            let path = PathExpanding.normalize(trimmed)
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
        if trimmed == "sushi" {
            return resolve()
        }
        // Bare name other than sushi — try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [trimmed]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
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

    static func isAvailable(command: String) -> Bool {
        let tokens = CommandTokenizer.tokenize(command)
        guard let first = tokens.first else { return resolve() != nil }
        return resolve(fromCommandToken: first) != nil
    }
}
