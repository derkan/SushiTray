import Foundation
import AppKit

/// Coding agents supported by `sushi launch <agent>`.
enum AgentsCatalog {
    /// Fallback if `sushi launch` cannot be probed.
    static let defaults = [
        "claude", "pi", "omp", "opencode", "codex", "hermes", "aider",
    ]

    private static let lock = NSLock()
    private static var cached: [String]?
    private static var cachedBinary: String?

    /// Returns agent names, probing `sushi launch` once per binary path.
    static func list(sushiBinary: String?) -> [String] {
        guard let binary = sushiBinary, !binary.isEmpty else { return defaults }

        lock.lock()
        if cachedBinary == binary, let cached { lock.unlock(); return cached }
        lock.unlock()

        let agents = probe(binary: binary) ?? defaults
        lock.lock()
        cached = agents
        cachedBinary = binary
        lock.unlock()
        return agents
    }

    private static func probe(binary: String) -> [String]? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["launch"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        // "supported: claude, pi, omp, …" or "agents: claude, pi, …"
        guard let match = text.range(
            of: #"(?:supported|agents):\s*([a-z0-9_,\s]+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let line = String(text[match])
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let list = line[line.index(after: colon)...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
        return list.isEmpty ? nil : list
    }
}

enum AgentLauncher {
    /// Opens Terminal and runs `sushi launch <agent> --url …` (optionally `--model`).
    static func launch(
        agent: String,
        sushiBinary: String,
        baseURL: URL,
        modelID: String?
    ) {
        var parts: [String] = [
            shellQuote(sushiBinary),
            "launch",
            shellQuote(agent),
            "--url",
            shellQuote(baseURL.absoluteString),
        ]
        if let modelID, !modelID.isEmpty {
            parts.append(contentsOf: ["--model", shellQuote(modelID)])
        }
        let command = parts.joined(separator: " ")
        runInTerminal(command)
    }

    private static func runInTerminal(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
            tell application "Terminal"
              activate
              do script "\(escaped)"
            end tell
            """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if error != nil {
                // Fallback: open via `open -a Terminal` + temp script
                launchViaOpen(command)
            }
        } else {
            launchViaOpen(command)
        }
    }

    private static func launchViaOpen(_ command: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sushitray-launch-\(UUID().uuidString).command")
        let body = "#!/bin/zsh\n\(command)\nexec /bin/zsh -i\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        NSWorkspace.shared.open(url)
    }

    private static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:@".contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
