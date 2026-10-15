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

    struct ComponentResult: Equatable {
        enum Outcome: Equatable {
            case updated
            case failed
            case skipped
            case openedReleases
        }

        var name: String
        var from: String?
        var to: String?
        var outcome: Outcome
        /// Short error / last brew line — never a full log dump.
        var detail: String?
    }

    struct UpdateResult: Equatable {
        var components: [ComponentResult]

        var sushiUpdated: Bool {
            components.contains { $0.name == "sushi" && $0.outcome == .updated }
        }

        var appUpdated: Bool {
            components.contains { $0.name == "SushiTray" && $0.outcome == .updated }
        }

        var hasFailure: Bool {
            components.contains { $0.outcome == .failed }
        }

        var hasSuccess: Bool {
            components.contains { $0.outcome == .updated || $0.outcome == .openedReleases }
        }

        var summaryLines: [String] {
            components.compactMap { component in
                switch component.outcome {
                case .updated:
                    if let from = component.from, let to = component.to {
                        return "\(component.name) \(from) → \(to)"
                    }
                    if let to = component.to {
                        return "\(component.name) → \(to)"
                    }
                    return "\(component.name) updated"
                case .failed:
                    if let detail = component.detail, !detail.isEmpty {
                        return "\(component.name) failed: \(detail)"
                    }
                    return "\(component.name) failed"
                case .skipped:
                    return nil
                case .openedReleases:
                    return "\(component.name): opened GitHub Releases"
                }
            }
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
    static func applyUpdates(from report: Report) async -> UpdateResult {
        var components: [ComponentResult] = []
        if report.sushiNeedsUpdate {
            components.append(await runUpdateSushi(from: report.sushiInstalled, expected: report.sushiLatest))
        }
        if report.appNeedsUpdate {
            components.append(await runUpdateApp(from: report.appInstalled, expected: report.appLatest))
        }
        return UpdateResult(components: components)
    }

    /// Relaunches this app bundle, then terminates the current process.
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        // Fallback if the completion is delayed or skipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.terminate(nil)
        }
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
        let (_, out) = await runCapture(executable: binary, arguments: ["--version"])
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
        let (_, out) = await runCapture(executable: binary, arguments: ["update", "--check"])
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

    private static func runUpdateSushi(from: String?, expected: String?) async -> ComponentResult {
        let fromVersion = from
        let (exitCode, output): (Int32, String)
        if await brewHasFormula("sushi") {
            (exitCode, output) = await runCapture(
                executable: "/opt/homebrew/bin/brew",
                arguments: ["upgrade", "beamivalice/tap/sushi"],
                fallback: "/usr/local/bin/brew"
            )
        } else if let binary = SushiBinary.resolve() {
            (exitCode, output) = await runCapture(executable: binary, arguments: ["update"])
        } else {
            return ComponentResult(
                name: "sushi",
                from: fromVersion,
                to: expected,
                outcome: .failed,
                detail: "binary not found"
            )
        }

        SushiBinary.clearCache()
        let newVersion = await installedSushiVersion()

        if let fromVersion, let newVersion, compareVersions(newVersion, fromVersion) > 0 {
            return ComponentResult(
                name: "sushi",
                from: fromVersion,
                to: newVersion,
                outcome: .updated,
                detail: nil
            )
        }
        if exitCode == 0, let expected, let newVersion, compareVersions(newVersion, expected) >= 0 {
            return ComponentResult(
                name: "sushi",
                from: fromVersion,
                to: newVersion,
                outcome: .updated,
                detail: nil
            )
        }
        if exitCode == 0, newVersion != nil {
            // brew may report "already installed" with exit 0 — treat as updated when we asked to upgrade.
            return ComponentResult(
                name: "sushi",
                from: fromVersion,
                to: newVersion ?? expected,
                outcome: .updated,
                detail: nil
            )
        }
        return ComponentResult(
            name: "sushi",
            from: fromVersion,
            to: expected,
            outcome: .failed,
            detail: shortFailureDetail(from: output, exitCode: exitCode)
        )
    }

    private static func runUpdateApp(from: String?, expected: String?) async -> ComponentResult {
        if await brewHasCask("sushitray") {
            let (exitCode, output) = await runCapture(
                executable: "/opt/homebrew/bin/brew",
                arguments: ["upgrade", "--cask", "sushitray"],
                fallback: "/usr/local/bin/brew"
            )
            if exitCode == 0 {
                return ComponentResult(
                    name: "SushiTray",
                    from: from,
                    to: expected,
                    outcome: .updated,
                    detail: nil
                )
            }
            return ComponentResult(
                name: "SushiTray",
                from: from,
                to: expected,
                outcome: .failed,
                detail: shortFailureDetail(from: output, exitCode: exitCode)
            )
        }
        // Not brew-installed: open releases page.
        await MainActor.run {
            if let url = URL(string: "https://github.com/derkan/SushiTray/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
        return ComponentResult(
            name: "SushiTray",
            from: from,
            to: expected,
            outcome: .openedReleases,
            detail: nil
        )
    }

    private static func shortFailureDetail(from output: String, exitCode: Int32) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "exit \(exitCode)"
        }
        let line = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
            ?? trimmed
        if line.count <= 160 { return line }
        return String(line.prefix(157)) + "…"
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
    ) async -> (exitCode: Int32, output: String) {
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
                    cont.resume(returning: (-1, "command not found"))
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
                    cont.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: (process.terminationStatus, text))
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
