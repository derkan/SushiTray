import Foundation
import AppKit

/// Terminal apps that can host `sushi launch`.
enum PreferredTerminal: String, CaseIterable, Identifiable, Codable {
    case terminal = "Terminal"
    case iTerm2 = "iTerm"
    case warp = "Warp"
    case ghostty = "Ghostty"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iTerm2: return "iTerm2"
        case .warp: return "Warp"
        case .ghostty: return "Ghostty"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .terminal: return ["com.apple.Terminal"]
        case .iTerm2: return ["com.googlecode.iterm2"]
        case .warp: return ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .ghostty: return ["com.mitchellh.ghostty"]
        }
    }

    var applicationURL: URL? {
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        // Fallback by display name in /Applications
        let candidates = [
            "/Applications/\(displayName).app",
            "/Applications/\(rawValue).app",
            "\(NSHomeDirectory())/Applications/\(displayName).app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    var isInstalled: Bool { applicationURL != nil }

    static var installed: [PreferredTerminal] {
        allCases.filter(\.isInstalled)
    }

    static var `default`: PreferredTerminal {
        if terminal.isInstalled { return .terminal }
        return installed.first ?? .terminal
    }
}

/// Coding agents supported by `sushi launch <agent>`.
enum AgentsCatalog {
    static let defaults = [
        "claude", "pi", "omp", "opencode", "codex", "hermes", "aider",
    ]

    private static let lock = NSLock()
    private static var cached: [String]?
    private static var cachedBinary: String?

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
    /// Prompt for a working directory. Cancel / dismiss → home directory.
    static func chooseWorkingDirectory(
        agent: String,
        startingDirectory: String?
    ) -> String {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose working directory for \(agent)"
        panel.prompt = "Open Agent"
        panel.directoryURL = URL(
            fileURLWithPath: startingDirectory ?? NSHomeDirectory(),
            isDirectory: true
        )
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            return url.path
        }
        return NSHomeDirectory()
    }

    static func launch(
        agent: String,
        sushiBinary: String,
        baseURL: URL,
        modelID: String?,
        workingDirectory: String,
        terminal: PreferredTerminal
    ) {
        var parts: [String] = [
            "cd",
            shellQuote(workingDirectory),
            "&&",
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
        run(command: command, in: terminal)
    }

    private static func run(command: String, in terminal: PreferredTerminal) {
        switch terminal {
        case .terminal:
            if runAppleScriptTerminal(command) { return }
        case .iTerm2:
            if runAppleScriptITerm(command) { return }
        case .warp, .ghostty:
            break
        }
        launchViaScriptFile(command: command, terminal: terminal)
    }

    private static func runAppleScriptTerminal(_ command: String) -> Bool {
        let escaped = appleScriptEscape(command)
        let source = """
            tell application "Terminal"
              activate
              do script "\(escaped)"
            end tell
            """
        return executeAppleScript(source)
    }

    private static func runAppleScriptITerm(_ command: String) -> Bool {
        let escaped = appleScriptEscape(command)
        let source = """
            tell application "iTerm"
              activate
              if (count of windows) = 0 then
                create window with default profile
              else
                tell current window
                  create tab with default profile
                end tell
              end if
              tell current session of current window
                write text "\(escaped)"
              end tell
            end tell
            """
        return executeAppleScript(source)
    }

    private static func executeAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    private static func launchViaScriptFile(command: String, terminal: PreferredTerminal) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sushitray-launch-\(UUID().uuidString).command")
        let body = "#!/bin/zsh\n\(command)\nexec /bin/zsh -i\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )

        if let appURL = terminal.applicationURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: config,
                completionHandler: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:@".contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
