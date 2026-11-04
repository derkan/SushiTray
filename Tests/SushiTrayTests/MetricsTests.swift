import XCTest
@testable import SushiTray

final class MetricsTests: XCTestCase {
    private func sample(_ json: String) throws -> SushiMetrics {
        try SushiMetrics.decode(Data(json.utf8))
    }

    func testWireFormatAndRatesExcludeCachedPromptTokens() throws {
        let metrics = try sample(#"{"gauges":{"gpu_clock_mhz":338,"gpu_utilization_pct":0,"memory_mb":36147},"counters":{"requests_success_total":2},"sessions":[{"request_id":42,"phase":"decode","generated_tokens":10}],"requests":[{"t_ms":100,"prompt_tokens":1000,"cached_tokens":800,"outcome":"ok","prefill_seconds":0.5,"generated_tokens":100,"decode_seconds":2}]}"#)
        XCTAssertEqual(metrics.sessions?.first?.requestId, 42)
        XCTAssertEqual(metrics.gauges["gpu_clock_mhz"], 338)
        XCTAssertEqual(metrics.requests?.first?.prefillSpeed, 400)
        XCTAssertEqual(metrics.requests?.first?.decodeSpeed, 50)
    }

    func testPrefillPhaseIsAvailableBeforeAnyRequestFinishes() throws {
        let gaugeOnly = try sample(#"{"gauges":{"requests_prefilling":1},"sessions":[],"requests":[]}"#)
        XCTAssertTrue(gaugeOnly.isPrefilling)
        XCTAssertFalse(gaugeOnly.isDecoding)
        let sessionOnly = try sample(#"{"gauges":{"requests_prefilling":0},"sessions":[{"request_id":1,"phase":"prefill","generated_tokens":0}]}"#)
        XCTAssertTrue(sessionOnly.isPrefilling)
        let concurrent = try sample(#"{"gauges":{"requests_prefilling":1},"sessions":[{"request_id":2,"phase":"decode","generated_tokens":10}]}"#)
        XCTAssertTrue(concurrent.isPrefilling)
        XCTAssertTrue(concurrent.isDecoding)
        let idle = try sample(#"{"gauges":{"requests_prefilling":0},"sessions":[]}"#)
        XCTAssertFalse(idle.isPrefilling)
        XCTAssertFalse(idle.isDecoding)
        var tracker = MetricsTracker()
        _ = tracker.observe(gaugeOnly, at: 1)
        XCTAssertNil(tracker.lastPrefill)
    }

    func testPrefillProgressUsesPostCacheTargetAndHandlesUnknownOrIdle() throws {
        let partial = try sample(#"{"gauges":{"requests_prefilling":1,"prefill_tokens_live":2048,"prefill_tokens_expected":8192}}"#)
        XCTAssertEqual(partial.prefillProgress, 0.25)
        let unknown = try sample(#"{"gauges":{"requests_prefilling":1,"prefill_tokens_live":0,"prefill_tokens_expected":0}}"#)
        XCTAssertNil(unknown.prefillProgress)
        let idle = try sample(#"{"gauges":{"requests_prefilling":0,"prefill_tokens_live":2048,"prefill_tokens_expected":8192}}"#)
        XCTAssertNil(idle.prefillProgress)
        let over = try sample(#"{"gauges":{"requests_prefilling":1,"prefill_tokens_live":9000,"prefill_tokens_expected":8192}}"#)
        XCTAssertEqual(over.prefillProgress, 1)
        let missing = try sample(#"{"gauges":{"requests_prefilling":1}}"#)
        XCTAssertNil(missing.prefillProgress)
    }

    func testSingleActiveContextExcludesCachedSessions() throws {
        let metrics = try sample(#"{"gauges":{},"sessions":[{"request_id":42,"phase":"decode","generated_tokens":100,"context_tokens":76000,"context_length":131072},{"request_id":0,"phase":"cached","generated_tokens":0,"context_tokens":80000,"context_length":0}]}"#)
        XCTAssertEqual(metrics.activeSessions.count, 1)
        let context = try XCTUnwrap(metrics.singleSessionContext)
        XCTAssertEqual(context.usedTokens, 76000)
        XCTAssertEqual(context.limitTokens, 131072)
        XCTAssertEqual(context.fraction, 76000.0 / 131072, accuracy: 0.0001)
        let prefill = try sample(#"{"gauges":{},"sessions":[{"request_id":43,"phase":"prefill","generated_tokens":0,"context_tokens":2048,"context_length":8192}]}"#)
        XCTAssertEqual(prefill.singleSessionContext?.fraction, 0.25)
    }

    func testContextIsUnavailableForMultipleIdleOrUnknownLimits() throws {
        let multiple = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":1,"context_tokens":100,"context_length":1000},{"request_id":2,"phase":"prefill","generated_tokens":0,"context_tokens":100,"context_length":1000}]}"#)
        XCTAssertEqual(multiple.activeSessions.count, 2)
        XCTAssertNil(multiple.singleSessionContext)
        let cached = try sample(#"{"gauges":{},"sessions":[{"request_id":0,"phase":"cached","generated_tokens":0,"context_tokens":100,"context_length":1000}]}"#)
        XCTAssertNil(cached.singleSessionContext)
        let zeroLimit = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":1,"context_tokens":100,"context_length":0}]}"#)
        XCTAssertNil(zeroLimit.singleSessionContext)
        let missing = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":1}]}"#)
        XCTAssertNil(missing.singleSessionContext)
        let over = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":1,"context_tokens":1100,"context_length":1000}]}"#)
        XCTAssertEqual(over.singleSessionContext?.fraction, 1)
    }

    func testMemoryUsesSushiFootprintAgainstPhysicalRAM() throws {
        let metrics = try sample(#"{"gauges":{"memory_mb":36147}}"#)
        let total: UInt64 = 48 * 1_073_741_824
        XCTAssertEqual((metrics.memoryMB ?? 0) / 1024, 35.3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(metrics.memoryFraction(totalBytes: total)), 35.3 / 48, accuracy: 0.001)
        XCTAssertNil(try sample(#"{"gauges":{}}"#).memoryFraction(totalBytes: total))
        XCTAssertNil(try sample(#"{"gauges":{"memory_mb":-1}}"#).memoryMB)
        XCTAssertNil(metrics.memoryFraction(totalBytes: 0))
    }

    func testLiveDecodeMatchesRequestIDsAndSumsConcurrentSessions() throws {
        var tracker = MetricsTracker()
        let first = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":10},{"request_id":2,"phase":"decode","generated_tokens":5}]}"#)
        let second = try sample(#"{"gauges":{},"sessions":[{"request_id":1,"phase":"decode","generated_tokens":30},{"request_id":2,"phase":"decode","generated_tokens":15},{"request_id":3,"phase":"decode","generated_tokens":500}]}"#)
        XCTAssertNil(tracker.observe(first, at: 10))
        XCTAssertEqual(tracker.observe(second, at: 12), 15)
        tracker.interrupt()
        XCTAssertNil(tracker.observe(second, at: 14))
    }

    func testLastRequestRatesSurviveIdlePollButDoNotDivideByZero() throws {
        var tracker = MetricsTracker()
        let done = try sample(#"{"gauges":{},"requests":[{"t_ms":1000,"prompt_tokens":100,"cached_tokens":120,"outcome":"ok","prefill_seconds":0,"generated_tokens":20,"decode_seconds":2}]}"#)
        _ = tracker.observe(done, at: 2)
        XCTAssertEqual(tracker.lastDecode, 10)
        XCTAssertNil(tracker.lastPrefill)
        _ = tracker.observe(try sample(#"{"gauges":{}}"#), at: 3)
        XCTAssertEqual(tracker.lastDecode, 10)
        XCTAssertEqual(tracker.sinceMilliseconds, 3000)
        XCTAssertThrowsError(try sample(#"{"error":"metrics disabled"}"#))
    }

    func testLastPrefillSurvivesNewPrefillAndInterruptedPolling() throws {
        var tracker = MetricsTracker()
        let done = try sample(#"{"gauges":{},"requests":[{"t_ms":1000,"prompt_tokens":1000,"cached_tokens":800,"outcome":"ok","prefill_seconds":0.5,"generated_tokens":20,"decode_seconds":2}]}"#)
        _ = tracker.observe(done, at: 2)
        XCTAssertEqual(tracker.lastPrefill, 400)
        let next = try sample(#"{"gauges":{"requests_prefilling":1,"prefill_tokens_live":2048,"prefill_tokens_expected":8192},"requests":[]}"#)
        _ = tracker.observe(next, at: 3)
        XCTAssertTrue(next.isPrefilling)
        XCTAssertEqual(next.prefillProgress, 0.25)
        XCTAssertEqual(tracker.lastPrefill, 400)
        tracker.interrupt()
        XCTAssertEqual(tracker.lastPrefill, 400)
        _ = tracker.observe(try sample(#"{"gauges":{},"requests":[]}"#), at: 4)
        XCTAssertEqual(tracker.lastPrefill, 400)
    }

    func testCachedModelsRemainDecodableAndPackUpdatesPersist() throws {
        let cached = try JSONDecoder().decode([SushiModel].self, from: Data(#"[{"id":"old-cache"}]"#.utf8))
        XCTAssertNil(cached.first?.packUpdate)
        let model = SushiModel(id: "pack", packUpdate: .init(current: "1", latest: "2", command: "sushi pull pack"))
        XCTAssertEqual(try JSONDecoder().decode(SushiModel.self, from: JSONEncoder().encode(model)), model)
    }

    func testServerPageURLsRespectCustomPort() {
        let connection = ServeCommandParser.Connection(host: "127.0.0.1", port: 23456, apiKey: "secret")
        XCTAssertEqual(connection.url(path: "/chat")?.absoluteString, "http://127.0.0.1:23456/chat")
        XCTAssertNil(connection.url(path: "/")?.query)
    }
}
