import XCTest
@testable import SushiTray

final class VersionTests: XCTestCase {
    func testSuccessfulNoOpDoesNotReportUpdate() {
        for name in ["SushiTray", "sushi"] {
            let result = UpdateChecker.verifiedUpdateResult(
                name: name, from: "1.1.1", expected: "1.1.2", installed: "1.1.1",
                exitCode: 0, output: "already installed"
            )
            XCTAssertEqual(result.outcome, .failed)
            XCTAssertTrue(result.detail?.contains("1.1.1") == true)
            XCTAssertTrue(result.detail?.contains("1.1.2") == true)
            let summary = UpdateChecker.UpdateResult(components: [result])
            XCTAssertFalse(summary.appUpdated)
            XCTAssertFalse(summary.sushiUpdated)
        }
    }

    func testUpdateRequiresVerifiedTargetVersion() {
        for (installed, exitCode, outcome) in [
            ("1.1.2", Int32(0), UpdateChecker.ComponentResult.Outcome.updated),
            ("1.1.3", 0, .updated),
            ("1.1.1", 0, .failed),
            (nil, 0, .failed),
            ("1.1.2", 1, .failed),
        ] as [(String?, Int32, UpdateChecker.ComponentResult.Outcome)] {
            let result = UpdateChecker.verifiedUpdateResult(
                name: "SushiTray", from: "1.1.0", expected: "1.1.2", installed: installed,
                exitCode: exitCode, output: "upgrade output"
            )
            XCTAssertEqual(result.outcome, outcome)
        }
    }

    func testAppVersionReadsReplacedPlist() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let plist = contents.appendingPathComponent("Info.plist")
        XCTAssertNil(UpdateChecker.installedAppVersion(at: bundle))
        for version in ["1.1.1", "1.1.2"] {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0
            )
            try data.write(to: plist, options: .atomic)
            XCTAssertEqual(UpdateChecker.installedAppVersion(at: bundle), version)
        }
    }

    func testVersionProbeUsesConfiguredBinary() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let content = "#!/bin/sh\n[ \"$1\" = \"--version\" ] || exit 7\nprintf 'sushi 1.5.0\\n'\n"
        try Data(content.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let version = await UpdateChecker.installedSushiVersion(binary: script.path)
        XCTAssertEqual(version, "1.5.0")
    }
}
