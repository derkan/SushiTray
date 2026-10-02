import Foundation
import Combine

final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    static let defaultCommand = """
    sushi serve --model ~/.sushi/models/Qwen3.8-Flash-Next-Sushi-2bpw \
      --mtp --kv-quant 8 --mtp-head-kv-quant --ctx-size 128000 \
      --max-tokens 32000 --prefix-cache-disk 20GB --prefix-cache-entries 1 \
      --prefix-cache-mem 1GB --temp 1 --skip-mem-preflight
    """

    private let defaults = UserDefaults.standard
    private let commandKey = "serveCommand"
    private let cachedModelsKey = "cachedModels"

    @Published var serveCommand: String {
        didSet { defaults.set(serveCommand, forKey: commandKey) }
    }

    private init() {
        if let saved = defaults.string(forKey: commandKey), !saved.isEmpty {
            serveCommand = saved
        } else {
            serveCommand = Self.defaultCommand
        }
    }

    var logFilePath: String {
        ServeCommandParser.logFilePath(fromCommand: serveCommand)
    }

    var connection: ServeCommandParser.Connection {
        ServeCommandParser.connection(fromCommand: serveCommand)
    }

    var sushiAvailable: Bool {
        SushiBinary.isAvailable(command: serveCommand)
    }

    func loadCachedModels() -> [SushiModel] {
        guard let data = defaults.data(forKey: cachedModelsKey) else { return [] }
        return (try? JSONDecoder().decode([SushiModel].self, from: data)) ?? []
    }

    func saveCachedModels(_ models: [SushiModel]) {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: cachedModelsKey)
        }
    }

    func setModel(_ modelPathOrID: String) {
        serveCommand = ServeCommandParser.replacingModel(
            in: serveCommand,
            modelPath: modelPathOrID
        )
    }
}

struct SushiModel: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var loaded: Bool?
    var state: String?
    var bytesOnDisk: UInt64?

    var displayName: String { id }

    init(id: String, loaded: Bool? = nil, state: String? = nil, bytesOnDisk: UInt64? = nil) {
        self.id = id
        self.loaded = loaded
        self.state = state
        self.bytesOnDisk = bytesOnDisk
    }
}
