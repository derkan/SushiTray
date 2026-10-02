import Foundation

final class SushiLogParser {
    private let streamedRegex: NSRegularExpression
    private let tokensRegex: NSRegularExpression
    private let chatURLRegex: NSRegularExpression

    init() {
        streamedRegex = try! NSRegularExpression(
            pattern: #"prefill:\s*([\d.]+)\s*tok/s.*?decode:\s*([\d.]+)\s*tok/s"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        tokensRegex = try! NSRegularExpression(
            pattern: #"<-\s*(\d+)\+(\d+)\s+tokens streamed"#,
            options: [.caseInsensitive]
        )
        chatURLRegex = try! NSRegularExpression(
            pattern: #"chat in your browser:\s*(https?://\S+)"#,
            options: [.caseInsensitive]
        )
    }

    struct Sample {
        var prefill: Double
        var decode: Double
        var promptTokens: Int?
        var generatedTokens: Int?
    }

    func parse(_ line: String) -> Sample? {
        let cleaned = line.replacingOccurrences(of: "\0", with: "")
        let ns = cleaned as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = streamedRegex.firstMatch(in: cleaned, options: [], range: full),
              match.numberOfRanges >= 3,
              let prefillRange = Range(match.range(at: 1), in: cleaned),
              let decodeRange = Range(match.range(at: 2), in: cleaned),
              let prefill = Double(cleaned[prefillRange]),
              let decode = Double(cleaned[decodeRange])
        else { return nil }

        var prompt: Int?
        var generated: Int?
        if let tMatch = tokensRegex.firstMatch(in: cleaned, options: [], range: full),
           tMatch.numberOfRanges >= 3,
           let pRange = Range(tMatch.range(at: 1), in: cleaned),
           let gRange = Range(tMatch.range(at: 2), in: cleaned)
        {
            prompt = Int(cleaned[pRange])
            generated = Int(cleaned[gRange])
        }

        return Sample(
            prefill: prefill,
            decode: decode,
            promptTokens: prompt,
            generatedTokens: generated
        )
    }

    /// Extracts `http://…` from lines like `chat in your browser: http://127.0.0.1:12345/`.
    func parseChatURL(_ line: String) -> URL? {
        let cleaned = line.replacingOccurrences(of: "\0", with: "")
        let ns = cleaned as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = chatURLRegex.firstMatch(in: cleaned, options: [], range: full),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: cleaned)
        else { return nil }
        var raw = String(cleaned[range])
        while raw.last == "." || raw.last == "," || raw.last == ")" {
            raw.removeLast()
        }
        return URL(string: raw)
    }
}
