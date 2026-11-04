import Foundation

/// Sushi 1.5's metrics feed, also used by upstream sushibar.
struct SushiMetrics: Decodable {
    struct Session: Decodable {
        var requestId: UInt64
        var phase: String
        var generatedTokens: UInt64
        var contextTokens: UInt64?
        var contextLength: UInt64?
    }

    struct ContextUsage: Equatable {
        var usedTokens: UInt64
        var limitTokens: UInt64

        var fraction: Double { min(1, Double(usedTokens) / Double(limitTokens)) }
    }

    struct Request: Decodable {
        var tMs: Int64
        var promptTokens: UInt64
        var cachedTokens: UInt64
        var outcome: String
        var prefillSeconds: Double
        var generatedTokens: UInt64
        var decodeSeconds: Double

        var prefillSpeed: Double? {
            guard outcome == "ok", promptTokens > cachedTokens, prefillSeconds > 0 else { return nil }
            return Double(promptTokens - cachedTokens) / prefillSeconds
        }

        var decodeSpeed: Double? {
            guard generatedTokens > 0, decodeSeconds > 0 else { return nil }
            return Double(generatedTokens) / decodeSeconds
        }
    }

    var gauges: [String: Double]
    var sessions: [Session]?
    var requests: [Request]?

    /// Cached entries describe idle conversations, not active requests.
    var activeSessions: [Session] {
        (sessions ?? []).filter { $0.phase == "prefill" || $0.phase == "decode" }
    }

    var singleSessionContext: ContextUsage? {
        let active = activeSessions
        guard active.count == 1, let session = active.first,
              let used = session.contextTokens,
              let limit = session.contextLength, limit > 0 else { return nil }
        return ContextUsage(usedTokens: used, limitTokens: limit)
    }

    var isPrefilling: Bool {
        (gauges["requests_prefilling"] ?? 0) > 0 || (sessions ?? []).contains { $0.phase == "prefill" }
    }

    /// Chunk-level progress through the post-cache prompt tail, not the whole context.
    var prefillProgress: Double? {
        guard isPrefilling,
              let expected = gauges["prefill_tokens_expected"], expected.isFinite, expected > 0,
              let processed = gauges["prefill_tokens_live"], processed.isFinite, processed >= 0 else { return nil }
        return min(1, processed / expected)
    }

    var isDecoding: Bool {
        (sessions ?? []).contains { $0.phase == "decode" }
    }

    /// Dashboard's memory_mb gauge is the Sushi process footprint in MiB.
    var memoryMB: Double? {
        guard let value = gauges["memory_mb"], value.isFinite, value >= 0 else { return nil }
        return value
    }

    func memoryFraction(totalBytes: UInt64) -> Double? {
        guard let memoryMB, totalBytes > 0 else { return nil }
        return min(1, memoryMB * 1_048_576 / Double(totalBytes))
    }

    static func decode(_ data: Data) throws -> SushiMetrics {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

struct DecodePoint {
    var time: TimeInterval
    /// nil marks an outage; zero is a healthy, idle server.
    var tokensPerSecond: Double?
}

/// Match sessions by request ID: a new request's existing tokens must not inflate live speed.
struct MetricsTracker {
    private var previous: [UInt64: UInt64] = [:]
    private var previousTime: TimeInterval?
    private(set) var sinceMilliseconds: Int64 = 0
    private(set) var lastDecode: Double?
    private(set) var lastPrefill: Double?

    mutating func observe(_ sample: SushiMetrics, at time: TimeInterval) -> Double? {
        let requests = sample.requests ?? []
        if let speed = requests.filter({ $0.decodeSpeed != nil }).max(by: { $0.tMs < $1.tMs })?.decodeSpeed {
            lastDecode = speed
        }
        if let speed = requests.filter({ $0.prefillSpeed != nil }).max(by: { $0.tMs < $1.tMs })?.prefillSpeed {
            lastPrefill = speed
        }
        sinceMilliseconds = max(sinceMilliseconds, Int64(time * 1000), requests.map(\.tMs).max() ?? 0)
        var current: [UInt64: UInt64] = [:]
        for session in sample.sessions ?? [] where session.phase == "decode" {
            current[session.requestId] = session.generatedTokens
        }
        defer {
            previous = current
            previousTime = time
        }
        guard let previousTime, time > previousTime else { return nil }
        var added: Double = 0
        var matched = false
        for (id, tokens) in current {
            guard let old = previous[id], tokens >= old else { continue }
            added += Double(tokens - old)
            matched = true
        }
        return matched ? added / (time - previousTime) : nil
    }

    mutating func interrupt() {
        previous = [:]
        previousTime = nil
    }
}

enum MetricsClient {
    static func fetch(
        connection: ServeCommandParser.Connection,
        since: Int64,
        session: URLSession = .shared
    ) async throws -> SushiMetrics {
        guard let url = connection.url(path: "/metrics.json") else { throw URLError(.badURL) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "since", value: String(since))]
        var request = URLRequest(url: components.url!, timeoutInterval: 3)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let key = connection.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "SushiMetrics", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: http.statusCode == 401
                    ? "Metrics access denied. Check the serve command's API key."
                    : "Metrics unavailable (HTTP \(http.statusCode)). Sushi 1.5.0 or newer is required."
            ])
        }
        return try SushiMetrics.decode(data)
    }
}
