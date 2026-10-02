import Foundation

enum ModelDiscovery {
    /// Scans model directories derived from the serve command.
    static func scanDisk(command: String) -> [SushiModel] {
        let tokens = CommandTokenizer.tokenize(command)
        var roots = ServeCommandParser.modelDirs(from: tokens)

        if roots.isEmpty {
            if let modelPath = ServeCommandParser.modelPath(from: tokens) {
                let parent = (modelPath as NSString).deletingLastPathComponent
                if !parent.isEmpty {
                    roots = [parent]
                }
            }
        }

        if roots.isEmpty {
            roots = [PathExpanding.normalize(ServeCommandParser.defaultModelDir)]
        }

        var seen = Set<String>()
        var models: [SushiModel] = []
        let fm = FileManager.default

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                let name = url.lastPathComponent
                guard seen.insert(name).inserted else { continue }
                let size = directorySize(at: url)
                models.append(SushiModel(id: name, bytesOnDisk: size))
            }
        }

        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// Resolves a filesystem path for a model id using command roots.
    static func path(forModelID id: String, command: String) -> String {
        let tokens = CommandTokenizer.tokenize(command)
        var roots = ServeCommandParser.modelDirs(from: tokens)
        if roots.isEmpty {
            if let modelPath = ServeCommandParser.modelPath(from: tokens) {
                roots = [(modelPath as NSString).deletingLastPathComponent]
            }
        }
        if roots.isEmpty {
            roots = [PathExpanding.normalize(ServeCommandParser.defaultModelDir)]
        }
        for root in roots {
            let candidate = (root as NSString).appendingPathComponent(id)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return (PathExpanding.normalize(ServeCommandParser.defaultModelDir) as NSString)
            .appendingPathComponent(id)
    }

    private static func directorySize(at url: URL) -> UInt64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += UInt64(size)
        }
        return total
    }
}
