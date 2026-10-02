import Foundation

enum ModelsClient {
    enum Source: Equatable {
        case api
        case cache
        case disk
    }

    struct Result {
        var models: [SushiModel]
        var source: Source
        var errorMessage: String?
    }

    private struct OpenAIModelsResponse: Decodable {
        struct Item: Decodable {
            var id: String
            var loaded: Bool?
            var state: String?
            var bytes_on_disk: UInt64?
        }

        var data: [Item]
    }

    /// Fetch models: API when running, else cache, else disk.
    static func resolve(
        isRunning: Bool,
        connection: ServeCommandParser.Connection,
        command: String,
        cached: [SushiModel]
    ) async -> Result {
        if isRunning {
            do {
                let models = try await fetchAPI(connection: connection)
                return Result(models: models, source: .api, errorMessage: nil)
            } catch {
                if !cached.isEmpty {
                    return Result(
                        models: cached,
                        source: .cache,
                        errorMessage: "failed to refresh"
                    )
                }
                let disk = ModelDiscovery.scanDisk(command: command)
                return Result(
                    models: disk,
                    source: .disk,
                    errorMessage: "failed to refresh"
                )
            }
        }

        if !cached.isEmpty {
            return Result(models: cached, source: .cache, errorMessage: nil)
        }

        let disk = ModelDiscovery.scanDisk(command: command)
        return Result(models: disk, source: .disk, errorMessage: nil)
    }

    static func fetchAPI(connection: ServeCommandParser.Connection) async throws -> [SushiModel] {
        let urlString = "http://\(connection.host):\(connection.port)/v1/models"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        if let key = connection.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map {
            SushiModel(
                id: $0.id,
                loaded: $0.loaded,
                state: $0.state,
                bytesOnDisk: $0.bytes_on_disk
            )
        }
    }
}
