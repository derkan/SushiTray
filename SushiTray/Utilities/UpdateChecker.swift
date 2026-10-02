import Foundation
import AppKit

/// Checks GitHub / CLI for newer sushi + SushiTray versions and can apply updates.
enum UpdateChecker {
    struct Report: Equatable {
        var sushiInstalled: String?
        var sushiLatest: String?
        var appInstalled: String
        var appLatest: String?

        var sushiNeedsUpdate: Bool {
            guard let installed = sushiInstalled, let latest = sushiLatest else { return false }
            return compareVersions(latest, installed) > 0
        }

        var appNeedsUpdate: Bool {
            guard let latest = appLatest else { return false }
            return compareVersions(latest, appInstalled) > 0
        }

        var hasAnyUpdate: Bool { sushiNeedsUpdate || appNeedsUpdate }

        var summary: String {
            var lines: [String] = []
            if let installed = sushiInstalled {
                if sushiNeedsUpdate, let latest = sushiLatest {
                    lines.append("sushi \(installed) → \(latest)")
                } else {
                    lines.append("sushi \(installed) (up to date)")
                }
            } else {
                lines.append("sushi not found")
            }
            if appNeedsUpdate, let latest = appLatest {
                lines.append("SushiTray \(appInstalled) → \(latest)")
            } else {
                lines.append("SushiTray \(appInstalled) (up to date)")
            }
            return lines.joined(separator: "\n")
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check() async -> Report {
        async let sushiPair = sushiVersions()
        async let appLatest = githubLatestTag(
            owner: "derkan",
            repo: "SushiTray"
        )
        let (sushiInstalled, sushiLatest) = await sushiPair
        return Report(
            sushiInstalled: sushiInstalled,
            sushiLatest: sushiLatest,
            appInstalled: appVersion,
            appLatest: await appLatest
        )
    }

    /// Runs brew/sushi update commands for components that need it.
    static func applyUpdates(from report: Report) async -> String {
        var log: [String] = []
        if report.sushiNeedsUpdate {
            log.append(await runUpdateSushi())
        }
        if report.appNeedsUpdate {
            log.append(await runUpdateApp())
        }
        return log.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Version discovery

    private static func sushiVersions() async -> (installed: String?, latest: String?) {
        let installed = await installedSushiVersion()
        // Prefer GitHub latest; fall back to parsing `sushi update --check`.
        let fromGitHub = await githubLatestTag(owner: "beamivalice", repo: "sushi")
        if let fromGitHub {
            return (installed, fromGitHub)
        }
        if let latest = await sushiUpdateCheckLatest() {
            return (installed, latest)
        }
        return (installed, installed)
    }

    private static func installedSushiVersion() async -> String? {
        guard let binary = SushiBinary.resolve() else { return nil }
        let out = await runCapture(executable: binary, arguments: ["--version"])
        // "sushi 1.1.1"
        if let match = out.range(of: #"sushi\s+([\d.]+)"#, options: .regularExpression) {
            let s = String(out[match])
            if let v = s.split(whereSeparator: { $0.isWhitespace }).last {
                return String(v)
            }
        }
        return nil
    }

    private static func sushiUpdateCheckLatest() async -> String? {
        guard let binary = SushiBinary.resolve() else { return nil }
        let out = await runCapture(executable: binary, arguments: ["update", "--check"])
        // "... (latest release 1.1.1)" or similar
        if let match = out.range(of: #"latest release\s+([\d.]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let s = String(out[match])
            if let v = s.split(whereSeparator: { $0.isWhitespace }).last {
                return String(v)
            }
        }
        return nil
    }

    private static func githubLatestTag(owner: String, repo: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("SushiTray/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            struct Release: Decodable { var tag_name: String }
            let release = try JSONDecoder().decode(Release.self, from: data)
            return normalizeTag(release.tag_name)
        } catch {
            return nil
        }
    }

    private static func normalizeTag(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("v") {
            t.removeFirst()
        }
        return t
    }

    // MARK: - Apply

    private static func runUpdateSushi() async -> String {
        // Prefer Homebrew when the formula is present; otherwise sushi's own updater.
        if await brewHasFormula("sushi") {
            let out = await runCapture(
                executable: "/opt/homebrew/bin/brew",
                arguments: ["upgrade", "beamivalice/tap/sushi"],
                fallback: "/usr/local/bin/brew"
            )
            return "sushi (brew): \(out.isEmpty ? "done" : out)"
        }
        guard let binary = SushiBinary.resolve() else {
            return "sushi: binary not found"
        }
        let out = await runCapture(executable: binary, arguments: ["update"])
        return "sushi update: \(out.isEmpty ? "done" : out)"
    }

    private static func runUpdateApp() async -> String {
        if await brewHasCask("sushitray") {
            let out = await runCapture(
                executable: "/opt/homebrew/bin/brew",
                arguments: ["upgrade", "--cask", "sushitray"],
                fallback: "/usr/local/bin/brew"
            )
            return "SushiTray (brew): \(out.isEmpty ? "done — quit and reopen the app" : out)"
        }
        // Not brew-installed: open releases page.
        await MainActor.run {
            if let url = URL(string: "https://github.com/derkan/SushiTray/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
        return "SushiTray: opened GitHub Releases (not installed via Homebrew)"
    }

    private static func brewHasCask(_ name: String) async -> Bool {
        await brewSucceeds(arguments: ["list", "--cask", name])
    }

    private static func brewHasFormula(_ name: String) async -> Bool {
        await brewSucceeds(arguments: ["list", "--formula", name])
    }

    private static func brewSucceeds(arguments: [String]) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                guard let path = candidates.first(where: {
                    FileManager.default.isExecutableFile(atPath: $0)
                }) else {
                    cont.resume(returning: false)
                    return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
                process.environment = env
                do {
                    try process.run()
                    process.waitUntilExit()
                    cont.resume(returning: process.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Process helpers

    private static func runCapture(
        executable: String,
        arguments: [String],
        fallback: String? = nil
    ) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let path: String
                if FileManager.default.isExecutableFile(atPath: executable) {
                    path = executable
                } else if let fallback,
                          FileManager.default.isExecutableFile(atPath: fallback)
                {
                    path = fallback
                } else {
                    cont.resume(returning: "")
                    return
                }
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                var env = ProcessInfo.processInfo.environment
                let brewPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                if let existing = env["PATH"] {
                    env["PATH"] = brewPaths + ":" + existing
                } else {
                    env["PATH"] = brewPaths
                }
                process.environment = env
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    cont.resume(returning: error.localizedDescription)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: text)
            }
        }
    }

    /// Returns negative if a < b, 0 if equal, positive if a > b.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
