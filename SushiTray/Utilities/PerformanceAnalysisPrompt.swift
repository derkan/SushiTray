import Foundation

enum PerformanceAnalysisPrompt {
    static let body = """
    You are an expert performance engineer specializing in the Sushi inference engine (beamivalice/sushi). You have deep knowledge of its source code, architecture (EXL3 experts, MTP, prefix cache, KV quantization, GDN/QSA, expert streaming, reasoning budget, loop-stop, etc.), and official documentation.

    The user will provide:
    1. The exact `sushi serve` command they are currently running
    2. Measured system RAM (physical total and current used/free)
    3. Server logs (as long and detailed as possible)
    4. The live `sushi serve -h` help text for the binary they are running

    Your task:

    1. Perform a deep analysis of the logs:
       - Prefill / decode speeds
       - Prefix cache hit rates and disk/RAM usage
       - MTP acceptance rate and regime gate behavior
       - Context length, thinking token counts, tool-call density
       - Memory pressure, evictions, resident size
       - Loop-stop, think-bound, QSA, GDN events
       - Signs of sub-agent / multi-session usage

    2. Treat the provided system RAM figures as ground truth for hardware class and headroom. Do not infer total RAM from logs unless the numbers are missing.

    3. Based on Sushi’s source code behavior and known trade-offs, recommend the **most performant** `sushi serve` command for this specific system and workload.

    When making recommendations, carefully consider:
    - RAM class limits (48GB / 64GB / 96GB+)
    - Agent workloads (Pi + sub-agents): preserve-thinking, prefix-cache-entries, reasoning budget balance
    - Prefill vs decode priority
    - Memory vs speed trade-offs (kv-quant 4 vs 8, prefix-cache-mem, ssd-budget, etc.)
    - Avoiding unnecessarily high ctx-size, entries, or memory values
    - Known edge cases and best practices from the codebase
    - Only recommend flags/options that appear in the provided `sushi serve -h` output. That help text is the authoritative list of parameters available on this installed binary; do not invent deprecated or unsupported flags.

    Additional hard constraints:
    - Prefer the smallest number of flags that actually matter. Do not add advanced MTP knobs (--max-mtp-ctx, --mtp-history-window, --mtp-min-depth, etc.) unless the logs clearly show a problem that those flags solve.
    - On 48 GB + Sushi-2bpw + kv-quant 4, the practical context ceiling is ~180-192k. Do not drop below 160k unless memory pressure is extreme.
    - Keep --prefill-chunk at 2048 unless logs show repeated "chunk stepped down" messages.
    - Only recommend --no-vision when the user explicitly says they do not use images, or the logs prove vision is never used.
    - Prefer --reasoning-budget in the 8k–16k range for agent work; do not cut max-tokens below 20k without strong evidence.
    - Never invent or recommend flags that do not appear in the provided `sushi serve -h` output.

    Output format:
    - Short diagnosis (current state of the system and main bottlenecks)
    - Recommended full `sushi serve` command (copy-paste ready)
    - Brief justification for every important parameter change
    - Optional: alternative versions (more memory-aggressive / higher-speed)

    Stay strictly technical, precise, and actionable. Base everything on the logs + code knowledge. No speculation.
    """

    /// Runs `<binary> serve -h` and returns combined stdout/stderr.
    static func fetchServeHelp(binary: String) -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve", "-h"]
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "(failed to run \(binary) serve -h: \(error.localizedDescription))"
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined: String
        if out.isEmpty {
            combined = err
        } else if err.isEmpty {
            combined = out
        } else {
            combined = out + "\n" + err
        }
        if combined.isEmpty {
            return "(empty help output from \(binary) serve -h; exit \(process.terminationStatus))"
        }
        return combined
    }

    static func message(serveCommand: String, logs: String, serveHelp: String) -> String {
        let command = serveCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let logBody = logs.trimmingCharacters(in: .whitespacesAndNewlines)
        let logSection = logBody.isEmpty ? "(no log content available)" : logBody
        let helpBody = serveHelp.trimmingCharacters(in: .whitespacesAndNewlines)
        let helpSection = helpBody.isEmpty
            ? "(sushi serve -h unavailable)"
            : helpBody
        return """
        \(body)

        ## Available `sushi serve` parameters

        The following is the live output of `sushi serve -h` from the binary in the serve command. These are the only flags/options you may use in recommendations:

        ```
        \(helpSection)
        ```

        ---

        ## 1. Exact `sushi serve` command

        ```
        \(command)
        ```

        ## 2. System RAM

        \(ramSummary())

        ## 3. Server logs

        ```
        \(logSection)
        ```
        """
    }

    private static func ramSummary() -> String {
        let snap = MemoryMetricsSampler.sample()
        let usedPct = Int((snap.usedFraction * 100).rounded())
        return """
        - Physical total: \(byteString(snap.totalBytes)) (\(snap.totalBytes) bytes)
        - Used: \(byteString(snap.usedBytes)) (\(usedPct)%)
        - Free (incl. speculative): \(byteString(snap.freeBytes))
        """
    }

    private static func byteString(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        }
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
