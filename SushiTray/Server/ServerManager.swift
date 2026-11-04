import Foundation
import Combine
import Darwin

final class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published private(set) var isRunning = false
    /// True while the Sushi 1.5 metrics endpoint answers.
    @Published private(set) var isReady = false
    @Published private(set) var modelState: ModelsClient.LoadState?
    @Published private(set) var isPrefilling = false
    @Published private(set) var prefillProgress: Double?
    @Published private(set) var isDecoding = false
    @Published private(set) var prefillTokensPerSecond: Double?
    @Published private(set) var genTokensPerSecond: Double?
    @Published private(set) var contextUsage: SushiMetrics.ContextUsage?
    @Published private(set) var activeSessionCount = 0
    @Published private(set) var gpuUtilization: Double?
    @Published private(set) var serverMemoryFraction: Double?
    @Published private(set) var errorMessage: String?
    @Published private(set) var chatURL: URL?

    private(set) var decodeHistory: [DecodePoint] = []
    @Published private(set) var metricsError: String?
    @Published private(set) var gpuClockMHz: Double?
    @Published private(set) var serverMemoryMB: Double?

    /// Fired on the main run-loop tick (for menu label refresh).
    var onTick: (() -> Void)?

    let logTailer = LogTailer(maxLines: 100)
    private var process: Process?
    private var intentionalStop = false
    private var metricsTracker = MetricsTracker()
    private var metricsTask: Task<Void, Never>?
    private var launchConnection: ServeCommandParser.Connection?
    private var sessionID = UUID()
    private var launchedModelID: String?
    private var tickTimer: Timer?

    init() {}

    func prepareLogTail(command: String) {
        let path = ServeCommandParser.logFilePath(fromCommand: command)
        logTailer.start(path: path)
    }

    func start(command: String) {
        guard !isRunning else { return }
        intentionalStop = false
        errorMessage = nil
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
            launchedModelID = ServeCommandParser.modelPath(from: CommandTokenizer.tokenize(command))
                .map { ($0 as NSString).lastPathComponent }
            modelState = nil
            launchConnection = launch.connection
            logTailer.reload(path: launch.logPath)
            launchOwnedProcess(binary: launch.binary, args: launch.args)
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
        tickTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let tickTimer {
            tickTimer.tolerance = 0.1
            RunLoop.main.add(tickTimer, forMode: .common)
        }
        tick()
    }

    func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        metricsTask?.cancel()
        metricsTask = nil
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
                if self.process === proc {
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
            decodeHistory = []
            pollMetrics()
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            markStopped()
        }
    }

    private func markStopped() {
        isRunning = false
        isReady = false
        isPrefilling = false
        prefillProgress = nil
        isDecoding = false
        if chatURL != nil { chatURL = nil }
        assign(\.prefillTokensPerSecond, nil)
        assign(\.genTokensPerSecond, nil)
        assign(\.gpuUtilization, nil)
        serverMemoryFraction = nil
        contextUsage = nil
        activeSessionCount = 0
        sessionID = UUID()
        modelState = nil
        launchedModelID = nil
        metricsTask?.cancel()
        metricsTask = nil
        metricsTracker = MetricsTracker()
        launchConnection = nil
        metricsError = nil
        gpuClockMHz = nil
        serverMemoryMB = nil
    }

    private func tick() {
        pollMetrics()
        onTick?()
    }

    private func pollMetrics() {
        guard isRunning, metricsTask == nil, let connection = launchConnection else { return }
        let id = sessionID
        let since = metricsTracker.sinceMilliseconds
        let started = Date().timeIntervalSince1970
        metricsTask = Task { @MainActor [weak self] in
            do {
                let sample = try await MetricsClient.fetch(connection: connection, since: since)
                guard let self, !Task.isCancelled, self.sessionID == id, self.isRunning else { return }
                self.metricsTask = nil
                self.applyMetrics(sample, at: started)
                self.onTick?()
            } catch {
                guard let self, !Task.isCancelled, self.sessionID == id else { return }
                self.metricsTask = nil
                self.metricsTracker.interrupt()
                self.recordDecode(nil, at: started)
                self.publishIfChanged(\.metricsError, error.localizedDescription)
                self.publishIfChanged(\.isReady, false)
                self.publishIfChanged(\.contextUsage, nil)
                self.publishIfChanged(\.activeSessionCount, 0)
                self.publishIfChanged(\.isPrefilling, false)
                self.publishIfChanged(\.prefillProgress, nil)
                self.publishIfChanged(\.isDecoding, false)
                self.publishIfChanged(\.chatURL, nil)
                self.assign(\.genTokensPerSecond, nil)
                self.assign(\.prefillTokensPerSecond, self.metricsTracker.lastPrefill)
                self.assign(\.gpuUtilization, nil)
                self.publishIfChanged(\.gpuClockMHz, nil)
                self.publishIfChanged(\.serverMemoryMB, nil)
                self.publishIfChanged(\.serverMemoryFraction, nil)
                self.onTick?()
            }
        }
    }

    func applyMetrics(_ sample: SushiMetrics, at started: TimeInterval) {
        let live = metricsTracker.observe(sample, at: started)
        publishIfChanged(\.activeSessionCount, sample.activeSessions.count)
        publishIfChanged(\.contextUsage, sample.singleSessionContext)
        publishIfChanged(\.isPrefilling, sample.isPrefilling)
        publishIfChanged(\.prefillProgress, sample.prefillProgress)
        publishIfChanged(\.isDecoding, sample.isDecoding)
        let active = sample.isPrefilling || sample.isDecoding
        assign(\.genTokensPerSecond, active ? live : metricsTracker.lastDecode)
        assign(\.prefillTokensPerSecond, metricsTracker.lastPrefill)
        recordDecode(live ?? (active ? nil : 0), at: started)
        assign(\.gpuUtilization, sample.gauges["gpu_utilization_pct"].map { min(1, max(0, $0 / 100)) }, tolerance: 0.005)
        assign(\.gpuClockMHz, sample.gauges["gpu_clock_mhz"].flatMap { $0 > 0 ? $0 : nil })
        assign(\.serverMemoryMB, sample.memoryMB)
        publishIfChanged(\.serverMemoryFraction, sample.memoryFraction(totalBytes: ProcessInfo.processInfo.physicalMemory))
        publishIfChanged(\.metricsError, nil)
        publishIfChanged(\.isReady, true)
        publishIfChanged(\.chatURL, launchConnection?.url(path: "/chat"))
    }

    private func recordDecode(_ rate: Double?, at time: TimeInterval) {
        decodeHistory.removeAll { $0.time < time - 300 }
        decodeHistory.append(DecodePoint(time: time, tokensPerSecond: rate))
        if decodeHistory.count > 301 { decodeHistory.removeFirst(decodeHistory.count - 301) }
    }

    func updateModelState(models: [SushiModel]) {
        guard isRunning else { return }
        publishIfChanged(\.modelState, ModelsClient.loadState(models: models, preferredID: launchedModelID))
    }

    var sessionIdentifier: UUID { sessionID }

    var connection: ServeCommandParser.Connection? { launchConnection }

    func pageURL(path: String) -> URL? {
        guard isReady else { return nil }
        return launchConnection?.url(path: path)
    }

    private func publishIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ServerManager, Value>, _ value: Value) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    private func assign(_ keyPath: ReferenceWritableKeyPath<ServerManager, Double?>, _ value: Double?, tolerance: Double = 0.05) {
        switch (self[keyPath: keyPath], value) {
        case (nil, nil):
            return
        case let (a?, b?) where abs(a - b) < tolerance:
            return
        default:
            self[keyPath: keyPath] = value
        }
    }
}
