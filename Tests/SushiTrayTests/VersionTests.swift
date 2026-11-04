import XCTest
@testable import SushiTray

final class VersionTests: XCTestCase {
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
