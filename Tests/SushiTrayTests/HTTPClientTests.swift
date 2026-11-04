import XCTest
@testable import SushiTray

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class HTTPClientTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testMetricsSendsAuthenticationPortAndCursor() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:23456/metrics.json?since=1000")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (200, #"{"gauges":{"gpu_clock_mhz":338}}"#)
        }
        let client = session()
        defer { client.invalidateAndCancel() }
        let result = try await MetricsClient.fetch(connection: .init(host: "127.0.0.1", port: 23456, apiKey: "test-key"), since: 1000, session: client)
        XCTAssertEqual(result.gauges["gpu_clock_mhz"], 338)
    }

    func testUnauthorizedMetricsIsNotAcceptedAsReady() async {
        StubProtocol.handler = { _ in (401, #"{"error":"unauthorized"}"#) }
        let client = session()
        defer { client.invalidateAndCancel() }
        do {
            _ = try await MetricsClient.fetch(connection: .init(host: "127.0.0.1", port: 12345), since: 0, session: client)
            XCTFail("401 must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("API key")) }
    }

    func testModelsReadPackUpdateMetadataFromAPI() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
            return (200, #"{"data":[{"id":"pack","state":"ready","meta":{"pack_update":{"current":"1.0","latest":"2.0","command":"sushi pull pack"}}},{"id":"other","state":"unloaded"}]}"#)
        }
        let client = session()
        defer { client.invalidateAndCancel() }
        let models = try await ModelsClient.fetchAPI(connection: .init(host: "127.0.0.1", port: 12345, apiKey: "key"), session: client)
        XCTAssertEqual(models.first?.packUpdate?.latest, "2.0")
        XCTAssertEqual(models.first?.packUpdate?.command, "sushi pull pack")
        XCTAssertNil(models.last?.packUpdate)
    }
}
