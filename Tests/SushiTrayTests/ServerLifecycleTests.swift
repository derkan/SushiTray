import Darwin
import XCTest
@testable import SushiTray

final class ServerLifecycleTests: XCTestCase {
    @MainActor
    func testStopWaitsForUnreadyServerThatIgnoresSIGTERM() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let logFile = directory.appendingPathComponent("sushi.log")
        let server = ServerManager()
        defer { server.stopSynchronously() }

        let script = #"trap "" TERM; echo $$ > "$1"; exec /bin/sleep 30"#
        server.start(command: #"/bin/sh -c '\#(script)' sushi "\#(pidFile.path)" --log-file "\#(logFile.path)" --port 0"#)
        XCTAssertTrue(server.isRunning)
        XCTAssertFalse(server.isReady)

        var pid: pid_t?
        for _ in 0..<100 {
            if let data = try? String(contentsOf: pidFile, encoding: .utf8),
               let value = pid_t(data.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pid = value
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let childPID = try XCTUnwrap(pid)
        let stopped = expectation(description: "The server process has exited")
        stopped.expectedFulfillmentCount = 2

        for _ in 0..<2 {
            server.stop {
                let result = kill(childPID, 0)
                let error = errno
                XCTAssertEqual(result, -1)
                XCTAssertEqual(error, ESRCH)
                stopped.fulfill()
            }
        }

        await fulfillment(of: [stopped], timeout: 6)
        XCTAssertFalse(server.isRunning)
    }
}
