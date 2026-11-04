import Foundation

enum ModelsClient {
    enum LoadState: String {
        case loading, ready, error, unloaded
    }

    static func loadState(models: [SushiModel], preferredID: String?) -> LoadState {
        if let preferredID, let selected = models.first(where: { $0.id == preferredID }) {
            return state(of: selected)
        }
        if models.contains(where: { $0.state == "loading" }) { return .loading }
        if models.contains(where: { $0.state == "ready" || $0.loaded == true }) { return .ready }
        if models.contains(where: { $0.state == "error" }) { return .error }
        return .unloaded
    }

    private static func state(of model: SushiModel) -> LoadState {
        if let state = model.state, let known = LoadState(rawValue: state) { return known }
        return model.loaded == true ? .ready : .unloaded
    }

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
            struct Meta: Decodable { var pack_update: SushiModel.PackUpdate? }
            var meta: Meta?
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

    static func fetchAPI(connection: ServeCommandParser.Connection, session: URLSession = .shared) async throws -> [SushiModel] {
        guard let url = connection.url(path: "/v1/models") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        if let key = connection.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map {
            SushiModel(
                id: $0.id,
                loaded: $0.loaded,
                state: $0.state,
                bytesOnDisk: $0.bytes_on_disk,
                packUpdate: $0.meta?.pack_update
            )
        }
    }
}
