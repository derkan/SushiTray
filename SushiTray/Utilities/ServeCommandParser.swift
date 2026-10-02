import Foundation

/// Parses flags from a tokenized sushi serve command.
enum ServeCommandParser {
    struct Connection {
        var host: String
        var port: Int
        var apiKey: String?
    }

    struct LaunchError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct LaunchSpec {
        var binary: String
        var args: [String]
        var logPath: String
        var connection: Connection
    }

    static let defaultHost = "127.0.0.1"
    static let defaultPort = 12345
    static let defaultLogFile = "~/.sushi/logs/sushi.log"
    static let defaultModelDir = "~/.sushi/models"

    static func connection(from tokens: [String]) -> Connection {
        var host = defaultHost
        var port = defaultPort
        var apiKey: String?

        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t == "--host", i + 1 < tokens.count {
                host = tokens[i + 1]
                i += 2
                continue
            }
            if t == "--port", i + 1 < tokens.count, let p = Int(tokens[i + 1]) {
                port = p
                i += 2
                continue
            }
            if t == "--api-key", i + 1 < tokens.count {
                apiKey = tokens[i + 1]
                i += 2
                continue
            }
            if t == "--api-key-env", i + 1 < tokens.count {
                let envName = tokens[i + 1]
                apiKey = ProcessInfo.processInfo.environment[envName]
                i += 2
                continue
            }
            i += 1
        }

        if host == "0.0.0.0" || host == "localhost" {
            host = defaultHost
        }
        return Connection(host: host, port: port, apiKey: apiKey)
    }

    static func connection(fromCommand command: String) -> Connection {
        connection(from: CommandTokenizer.tokenize(command))
    }

    static func modelPath(from tokens: [String]) -> String? {
        guard let idx = tokens.firstIndex(of: "--model"), idx + 1 < tokens.count else {
            return nil
        }
        return PathExpanding.normalize(tokens[idx + 1])
    }

    static func modelDirs(from tokens: [String]) -> [String] {
        var dirs: [String] = []
        var i = 0
        while i < tokens.count {
            if tokens[i] == "--model-dir", i + 1 < tokens.count {
                dirs.append(PathExpanding.normalize(tokens[i + 1]))
                i += 2
                continue
            }
            i += 1
        }
        return dirs
    }

    static func logFilePath(from tokens: [String]) -> String {
        if let idx = tokens.firstIndex(of: "--log-file"), idx + 1 < tokens.count {
            let value = tokens[idx + 1]
            if value == "off" { return PathExpanding.normalize(defaultLogFile) }
            return PathExpanding.normalize(value)
        }
        return PathExpanding.normalize(defaultLogFile)
    }

    static func logFilePath(fromCommand command: String) -> String {
        logFilePath(from: CommandTokenizer.tokenize(command))
    }

    static func hasFlag(_ flag: String, in tokens: [String]) -> Bool {
        tokens.contains(flag)
    }

    /// Builds argv for Process: binary path + args with injected --log-file / --parent-pid.
    static func buildLaunchArguments(
        command: String,
        parentPID: Int32
    ) -> Result<LaunchSpec, LaunchError> {
        let tokens = CommandTokenizer.tokenize(command)
        guard let first = tokens.first else {
            return .failure(LaunchError(message: "Empty serve command."))
        }
        guard let binary = SushiBinary.resolve(fromCommandToken: first) else {
            return .failure(LaunchError(
                message: "sushi not found. Install with: brew install beamivalice/tap/sushi"
            ))
        }

        var args = Array(tokens.dropFirst())
        expandPathFlags(in: &args)

        if !hasFlag("--log-file", in: args) {
            let log = PathExpanding.normalize(defaultLogFile)
            ensureParentDirectory(log)
            args.append(contentsOf: ["--log-file", log])
        } else if let idx = args.firstIndex(of: "--log-file"), idx + 1 < args.count, args[idx + 1] != "off" {
            ensureParentDirectory(args[idx + 1])
        }

        if !hasFlag("--parent-pid", in: args) {
            args.append(contentsOf: ["--parent-pid", "\(parentPID)"])
        }

        let logPath = logFilePath(from: [first] + args)
        let conn = connection(from: [first] + args)
        return .success(LaunchSpec(
            binary: binary,
            args: args,
            logPath: logPath,
            connection: conn
        ))
    }

    /// Replaces or inserts `--model <path>` in the command string.
    static func replacingModel(in command: String, modelPath: String) -> String {
        let tokens = CommandTokenizer.tokenize(command)
        guard !tokens.isEmpty else { return command }
        var result = tokens
        if let idx = result.firstIndex(of: "--model"), idx + 1 < result.count {
            result[idx + 1] = modelPath
        } else if let serveIdx = result.firstIndex(of: "serve") {
            result.insert(contentsOf: ["--model", modelPath], at: serveIdx + 1)
        } else {
            result.insert(contentsOf: ["--model", modelPath], at: min(1, result.count))
        }
        return shellJoin(result)
    }

    private static func expandPathFlags(in args: inout [String]) {
        let pathFlags: Set<String> = ["--model", "--model-dir", "--log-file"]
        var i = 0
        while i < args.count {
            if pathFlags.contains(args[i]), i + 1 < args.count {
                args[i + 1] = PathExpanding.normalize(args[i + 1])
                i += 2
                continue
            }
            i += 1
        }
    }

    private static func ensureParentDirectory(_ filePath: String) {
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
    }

    private static func shellJoin(_ tokens: [String]) -> String {
        tokens.map { token in
            if token.contains(where: { $0.isWhitespace }) || token.contains("\"") {
                let escaped = token.replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return token
        }.joined(separator: " ")
    }
}
