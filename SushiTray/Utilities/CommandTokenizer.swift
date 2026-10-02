import Foundation

/// Shell-like tokenizer for Process argv (supports quotes, escapes, and `\` line continuation).
enum CommandTokenizer {
    static func tokenize(_ input: String) -> [String] {
        // Normalize shell line continuations before parsing.
        let normalized = input.replacingOccurrences(
            of: #"\\\r?\n"#,
            with: " ",
            options: .regularExpression
        )
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escape = false
        let chars = Array(normalized)

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escape {
                current.append(c)
                escape = false
                i += 1
                continue
            }
            if c == "\\" && !inSingle {
                escape = true
                i += 1
                continue
            }
            if c == "'" && !inDouble {
                inSingle.toggle()
                i += 1
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                i += 1
                continue
            }
            if (c == " " || c == "\t" || c == "\n" || c == "\r") && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
