import Foundation

enum PathExpanding {
    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + String(path.dropFirst())
    }

    static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return (expandTilde(trimmed) as NSString).standardizingPath
    }
}
