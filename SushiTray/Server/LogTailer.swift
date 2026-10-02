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

    init(maxLines: Int = 200) {
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
        // Also load last N lines for Settings display
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

    private func loadTail() {
        guard let path,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return }
        let text = String(decoding: stripNULs(data), as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let slice = Array(all.suffix(maxLines))
        DispatchQueue.main.async {
            self.lines = slice
        }
    }

    private func poll() {
        guard let path else { return }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64
        else { return }

        if size < lastSize {
            // Rotated or truncated
            try? fileHandle?.close()
            fileHandle = FileHandle(forReadingAtPath: path)
            lastSize = 0
            buffer = Data()
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

        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            {
                appendLine(line)
            }
        }
    }

    private func appendLine(_ line: String) {
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            self.onLine?(line)
        }
    }

    private func stripNULs(_ data: Data) -> Data {
        data.filter { $0 != 0 }
    }
}
