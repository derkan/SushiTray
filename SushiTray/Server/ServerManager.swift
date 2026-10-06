import Foundation
import Combine
import Darwin

final class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published private(set) var isRunning = false
    /// True after log shows `Server listening on http://…`.
    @Published private(set) var isReady = false
    @Published private(set) var prefillTokensPerSecond: Double?
    @Published private(set) var genTokensPerSecond: Double?
    @Published private(set) var gpuUtilization: Double?
    @Published private(set) var gpuMemoryFraction: Double?
    @Published private(set) var gpuMemoryUsedBytes: UInt64?
    @Published private(set) var errorMessage: String?
    @Published private(set) var port: Int = ServeCommandParser.defaultPort
    @Published private(set) var host: String = ServeCommandParser.defaultHost
    /// From log line `chat in your browser: http://…` while server is running.
    @Published private(set) var chatURL: URL?

    // Session serving stats
    @Published private(set) var sessionPrefill: Double?
    @Published private(set) var sessionDecode: Double?
    @Published private(set) var sessionPromptTokens: Int = 0
    @Published private(set) var sessionGeneratedTokens: Int = 0
    @Published private(set) var sessionRequests: Int = 0

    /// Fired on the main run-loop tick (for menu label refresh).
    var onTick: (() -> Void)?

    let logTailer = LogTailer(maxLines: 100)
    private let logParser = SushiLogParser()
    private var process: Process?
    private var intentionalStop = false
    private var prefillWindow = RollingMetric(window: 3)
    private var genWindow = RollingMetric(window: 3)
    private var tickTimer: Timer?
    private var currentLogPath: String?
    private var gpuTickCounter = 0
    private var didScanChatURLForSession = false

    private init() {
        logTailer.setOnLine { [weak self] line in
            self?.ingestLogLine(line)
        }
    }

    func prepareLogTail(command: String) {
        let path = ServeCommandParser.logFilePath(fromCommand: command)
        currentLogPath = path
        logTailer.start(path: path)
        scanLogsForChatURLOnce()
    }

    func start(command: String) {
        guard !isRunning else { return }
        intentionalStop = false
        errorMessage = nil
        didScanChatURLForSession = false
        chatURL = nil

        let result = ServeCommandParser.buildLaunchArguments(
            command: command,
            parentPID: getpid()
        )
        switch result {
        case .failure(let error):
            errorMessage = error.message
            return
        case .success(let launch):
            host = launch.connection.host
            port = launch.connection.port
            currentLogPath = launch.logPath
            logTailer.reload(path: launch.logPath)
            logTailer.markSessionStart()
            launchOwnedProcess(binary: launch.binary, args: launch.args)
            scanLogsForChatURLOnce()
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        intentionalStop = true
        let proc = process
        process = nil
        markStopped()
        if let proc, proc.isRunning {
            proc.gracefulTerminate {
                DispatchQueue.main.async { completion?() }
            }
        } else {
            completion?()
        }
    }

    func stopSynchronously(timeout: TimeInterval = 3.5) {
        intentionalStop = true
        let proc = process
        process = nil
        markStopped()
        guard let proc, proc.isRunning else { return }
        let pid = proc.processIdentifier
        proc.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    func restart(command: String) {
        stop { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.start(command: command)
            }
        }
    }

    func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Private

    private func launchOwnedProcess(binary: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.process == nil || self.process === proc {
                    self.process = nil
                    if !self.intentionalStop {
                        self.errorMessage =
                            "Server exited unexpectedly (code \(proc.terminationStatus))."
                    }
                    self.markStopped()
                }
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            isReady = false
            resetSessionStats()
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            markStopped()
        }
    }

    private func markStopped() {
        isRunning = false
        isReady = false
        if chatURL != nil { chatURL = nil }
        didScanChatURLForSession = false
        assign(&prefillTokensPerSecond, nil)
        assign(&genTokensPerSecond, nil)
        assign(&gpuUtilization, nil)
        assign(&gpuMemoryFraction, nil)
        if gpuMemoryUsedBytes != nil { gpuMemoryUsedBytes = nil }
        prefillWindow.reset()
        genWindow.reset()
        gpuTickCounter = 0
    }

    private func resetSessionStats() {
        sessionPrefill = nil
        sessionDecode = nil
        sessionPromptTokens = 0
        sessionGeneratedTokens = 0
        sessionRequests = 0
    }

    private func tick() {
        publishSpeedWindows()
        // GPU sample every 2s — IORegistry is the hot cost.
        gpuTickCounter += 1
        if isRunning, gpuTickCounter % 2 == 0 {
            if let gpu = GPUMetricsSampler.sample() {
                assign(&gpuUtilization, gpu.utilization)
                assign(&gpuMemoryFraction, gpu.memoryFraction)
                if gpuMemoryUsedBytes != gpu.memoryUsedBytes {
                    gpuMemoryUsedBytes = gpu.memoryUsedBytes
                }
            }
        } else if !isRunning {
            assign(&gpuUtilization, nil)
            assign(&gpuMemoryFraction, nil)
            if gpuMemoryUsedBytes != nil { gpuMemoryUsedBytes = nil }
        }
        onTick?()
    }

    private func ingestLogLine(_ line: String) {
        if isRunning, !isReady, logParser.isServerListening(line) {
            isReady = true
        }
        if chatURL == nil, let url = logParser.parseChatURL(line) {
            chatURL = url
            didScanChatURLForSession = true
        }
        guard let sample = logParser.parse(line) else { return }
        prefillWindow.record(sample.prefill)
        genWindow.record(sample.decode)
        sessionPrefill = sample.prefill
        sessionDecode = sample.decode
        sessionRequests += 1
        if let p = sample.promptTokens { sessionPromptTokens += p }
        if let g = sample.generatedTokens { sessionGeneratedTokens += g }
        publishSpeedWindows()
    }

    /// One-shot scan of the current in-memory tail. New lines go through `ingestLogLine`.
    func scanLogsForChatURLOnce() {
        guard !didScanChatURLForSession, chatURL == nil else { return }
        didScanChatURLForSession = true
        for line in logTailer.lines.reversed() {
            if let url = logParser.parseChatURL(line) {
                chatURL = url
                return
            }
        }
    }

    private func publishSpeedWindows() {
        assign(&prefillTokensPerSecond, prefillWindow.stickyLatest())
        assign(&genTokensPerSecond, genWindow.stickyLatest())
    }

    private func assign(_ target: inout Double?, _ value: Double?) {
        switch (target, value) {
        case (nil, nil):
            return
        case let (a?, b?) where abs(a - b) < 0.05:
            return
        default:
            target = value
        }
    }
}
