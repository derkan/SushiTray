import Foundation
import Combine

/// Tails a log file, publishing new lines. Binary-safe (strips NUL bytes).
final class LogTailer: ObservableObject {
    @Published private(set) var lines: [String] = []

    private var fileHandle: FileHandle?
    private var timer: Timer?
    private var path: String?
    private var maxLines: Int
    private var onLine: ((String) -> Void)?
    private var buffer = Data()
    private var lastSize: UInt64 = 0
    /// Byte offset of the log file when the current serve process started.
    private var sessionStartOffset: UInt64 = 0

    /// Bytes to read from EOF when seeding the in-memory tail.
    private let tailReadBytes: UInt64 = 64 * 1024

    init(maxLines: Int = 100) {
        self.maxLines = maxLines
    }

    func setOnLine(_ handler: @escaping (String) -> Void) {
        onLine = handler
    }

    func start(path: String) {
        if self.path == path, timer != nil { return }
        stop()
        self.path = path
        openAndSeekToEnd()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        loadTail()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? fileHandle?.close()
        fileHandle = nil
        buffer = Data()
        lastSize = 0
    }

    func reload(path: String) {
        stop()
        start(path: path)
    }

    /// Call immediately before spawning `sushi serve` so export skips prior runs.
    func markSessionStart() {
        sessionStartOffset = currentFileSize() ?? lastSize
    }

    /// Log text written since the last `markSessionStart()`, capped at `maxBytes` from EOF.
    func textSinceSessionStart(maxBytes: UInt64 = 512 * 1024) -> String {
        guard let path else { return "" }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size > 0,
              let handle = FileHandle(forReadingAtPath: path)
        else {
            return ""
        }
        defer { try? handle.close() }

        var start = sessionStartOffset
        if start > size {
            start = 0
        }
        var offset = start
        if size > start, size - start > maxBytes {
            offset = size - maxBytes
        }
        handle.seek(toFileOffset: offset)
        var data = stripNULs(handle.readDataToEndOfFile())
        if offset > start, let nl = data.firstIndex(of: 0x0A) {
            data = data.suffix(from: data.index(after: nl))
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentFileSize() -> UInt64? {
        guard let path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64
        else { return nil }
        return size
    }

    private func openAndSeekToEnd() {
        guard let path else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            let dir = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: nil)
        }
        fileHandle = FileHandle(forReadingAtPath: path)
        if let handle = fileHandle {
            handle.seekToEndOfFile()
            lastSize = handle.offsetInFile
        }
    }

    /// Reads only the last ~64KB of the log, not the entire file.
    private func loadTail() {
        guard let path else { return }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size > 0,
              let handle = FileHandle(forReadingAtPath: path)
        else {
            let clear = { self.lines = [] }
            if Thread.isMainThread { clear() } else { DispatchQueue.main.async(execute: clear) }
            return
        }
        defer { try? handle.close() }

        let offset = size > tailReadBytes ? size - tailReadBytes : 0
        handle.seek(toFileOffset: offset)
        var data = stripNULs(handle.readDataToEndOfFile())
        // If we started mid-file, drop the partial first line.
        if offset > 0, let nl = data.firstIndex(of: 0x0A) {
            data = data.suffix(from: data.index(after: nl))
        }
        let text = String(decoding: data, as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let slice = Array(all.suffix(maxLines))
        let apply = { self.lines = slice }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func poll() {
        guard let path else { return }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64
        else { return }

        if size < lastSize {
            // Rotated or truncated — re-seed from trailing bytes, don't slurp from 0.
            try? fileHandle?.close()
            fileHandle = FileHandle(forReadingAtPath: path)
            buffer = Data()
            loadTail()
            if let handle = fileHandle {
                handle.seekToEndOfFile()
                lastSize = handle.offsetInFile
            } else {
                lastSize = size
            }
            return
        }

        if fileHandle == nil {
            fileHandle = FileHandle(forReadingAtPath: path)
            fileHandle?.seekToEndOfFile()
            lastSize = fileHandle?.offsetInFile ?? 0
            return
        }

        guard let handle = fileHandle else { return }
        handle.seek(toFileOffset: lastSize)
        let chunk = handle.readDataToEndOfFile()
        guard !chunk.isEmpty else { return }
        lastSize = handle.offsetInFile
        buffer.append(stripNULs(chunk))

        var newLines: [String] = []
        // Split without quadratic removeSubrange on the whole buffer.
        var start = buffer.startIndex
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            let lineData = buffer[start..<nl]
            start = buffer.index(after: nl)
            if let line = String(data: Data(lineData), encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            {
                newLines.append(line)
            }
        }
        if start > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<start)
        }
        guard !newLines.isEmpty else { return }

        DispatchQueue.main.async {
            self.lines.append(contentsOf: newLines)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            for line in newLines {
                self.onLine?(line)
            }
        }
    }

    private func stripNULs(_ data: Data) -> Data {
        if data.contains(0) {
            return data.filter { $0 != 0 }
        }
        return data
    }
}
