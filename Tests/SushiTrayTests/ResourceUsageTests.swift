import XCTest
import Combine
import AppKit
import QuartzCore
@testable import SushiTray

final class ResourceUsageTests: XCTestCase {
    @MainActor
    func testLEDUsesLayerAnimationsAndStopsWhenDetached() async {
        _ = NSApplication.shared
        let bounds = NSRect(x: 0, y: 0, width: LEDMatrixLine.width, height: LEDMatrixLine.height)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = LEDMatrixLine.DisplayView(frame: bounds)
        window.contentView = view
        view.update(text: "S: loading", color: .systemOrange, progress: nil, shimmering: true)
        let layers = view.layer?.sublayers ?? []
        XCTAssertEqual(layers.count, 4)
        guard layers.count == 4, let shine = layers[3].sublayers?.first else { return }
        XCTAssertNotNil(shine.animation(forKey: "shine"))
        view.update(text: "S: ready", color: .systemGreen, progress: nil, shimmering: false)
        XCTAssertNil(shine.animation(forKey: "shine"))
        view.update(text: "P: prefill..", color: .white, progress: nil, shimmering: true)
        XCTAssertNotNil(shine.animation(forKey: "shine"))
        window.contentView = nil
        XCTAssertNil(shine.animation(forKey: "shine"))
    }

    func testIdenticalMetricsDoNotPublishViewUpdates() throws {
        let manager = ServerManager()
        let sample = try SushiMetrics.decode(Data(#"{"gauges":{"gpu_utilization_pct":42,"gpu_clock_mhz":338,"memory_mb":36147},"sessions":[],"requests":[]}"#.utf8))
        manager.applyMetrics(sample, at: 1000)
        var notifications = 0
        let subscription = manager.objectWillChange.sink { notifications += 1 }
        defer { subscription.cancel() }
        for second in 1001...1100 { manager.applyMetrics(sample, at: Double(second)) }
        XCTAssertEqual(notifications, 0, "Idle polling and hidden graph history must not invalidate SwiftUI")
        let changed = try SushiMetrics.decode(Data(#"{"gauges":{"gpu_utilization_pct":43,"gpu_clock_mhz":338,"memory_mb":36147},"sessions":[],"requests":[]}"#.utf8))
        manager.applyMetrics(changed, at: 1101)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(try XCTUnwrap(manager.gpuUtilization), 0.43, accuracy: 0.001)
    }

    func testDecodeHistoryIsBoundedToFiveMinutes() throws {
        let manager = ServerManager()
        let sample = try SushiMetrics.decode(Data(#"{"gauges":{},"sessions":[],"requests":[]}"#.utf8))
        for second in 0..<1000 { manager.applyMetrics(sample, at: Double(second)) }
        XCTAssertEqual(manager.decodeHistory.count, 301)
        XCTAssertEqual(manager.decodeHistory.first?.time, 699)
        XCTAssertEqual(manager.decodeHistory.last?.time, 999)
    }

    func testLogBurstKeepsOnlyBoundedTail() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let tailer = LogTailer(maxLines: 100)
        tailer.start(path: file.path)
        defer { tailer.stop() }
        let ready = expectation(description: "Latest marker reaches bounded log tail")
        let subscription = tailer.$lines.first { $0.last == "burst-end" }.sink { _ in ready.fulfill() }
        defer { subscription.cancel() }
        let burst = String(repeating: "log line\n", count: 300_000) + "burst-end\n"
        try Data(burst.utf8).write(to: file)
        wait(for: [ready], timeout: 3)
        XCTAssertLessThanOrEqual(tailer.lines.count, 100)
        XCTAssertLessThan(tailer.lines.joined().utf8.count, 64 * 1024)
    }

}
