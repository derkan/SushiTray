import Foundation

/// Shell-like tokenizer for Process argv (supports quotes, escapes, and `\` line continuation).
enum CommandTokenizer {
    /// macOS smart dashes turn `--` into `–`/`—`; restore ASCII hyphens for flags.
    static func restoringASCIIHyphens(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{2014}", with: "--") // em dash —
            .replacingOccurrences(of: "\u{2013}", with: "--") // en dash –
            .replacingOccurrences(
                of: #"(^|[\s])-{3,}"#,
                with: "$1--",
                options: .regularExpression
            )
    }

    static func tokenize(_ input: String) -> [String] {
        // Normalize shell line continuations before parsing.
        let normalized = restoringASCIIHyphens(input).replacingOccurrences(
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
