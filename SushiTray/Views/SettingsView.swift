import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var logTailer: LogTailer
    @State private var commandDraft: String = ""
    @State private var sushiMissing = false
    @State private var binaryCheckWorkItem: DispatchWorkItem?
    @State private var isPreparingAnalysis = false
    @State private var followLog = true

    init(config: AppConfig, serverManager: ServerManager) {
        self.config = config
        self.serverManager = serverManager
        self.logTailer = serverManager.logTailer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Serve Command")
                    .font(.headline)
                Spacer()
                Link(
                    "Sushi documentation on GitHub",
                    destination: URL(string: "https://github.com/beamivalice/sushi")!
                )
                .font(.callout)
            }

            CommandEditor(text: $commandDraft)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )

            Toggle("Autostart server", isOn: $config.autoStartServer)
                .toggleStyle(.checkbox)

            Toggle("Check for updates automatically", isOn: $config.checkForUpdates)
                .toggleStyle(.checkbox)

            HStack {
                Text("Terminal for agents")
                Spacer()
                Picker("", selection: $config.preferredTerminal) {
                    ForEach(PreferredTerminal.allCases) { terminal in
                        Text(terminalLabel(terminal))
                            .tag(terminal)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            if sushiMissing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("sushi was not found on this system.")
                        .foregroundStyle(.orange)
                    Text("Install with:")
                        .foregroundStyle(.secondary)
                    Text("brew install beamivalice/tap/sushi")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }

            HStack {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                Button("Reset to Default") {
                    commandDraft = AppConfig.defaultCommand
                }
                Spacer()
                if serverManager.isRunning {
                    Button("Restart") { saveAndRestart() }
                        .disabled(sushiMissing)
                    Button(isPreparingAnalysis ? "Preparing…" : "Analyze…") {
                        openPerformanceAnalysisChat()
                    }
                    .disabled(serverManager.chatURL == nil || isPreparingAnalysis)
                    .help("Copies the analysis prompt to the clipboard and opens chat")
                } else {
                    Button("Start") { saveAndStart() }
                        .disabled(sushiMissing)
                }
            }

            Divider()

            HStack {
                Text("Log Tail")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    logTailer.clearDisplayedLines()
                }
                .disabled(logTailer.lines.isEmpty)
                Button("Copy") {
                    copyLogTail()
                }
                .disabled(logTailer.lines.isEmpty)
                Toggle("Follow", isOn: $followLog)
                    .toggleStyle(.button)
                    .help("Scroll to the latest log lines as they arrive")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(
                        logTailer.lines.isEmpty
                            ? "(log empty — \(config.logFilePath))"
                            : logTailer.lines.joined(separator: "\n")
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id("log-bottom")
                }
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .onAppear {
                    if followLog {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: logTailer.lines.count) { _ in
                    guard followLog else { return }
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
                .onChange(of: followLog) { enabled in
                    if enabled {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            commandDraft = CommandTokenizer.restoringASCIIHyphens(config.serveCommand)
            refreshBinaryStatusImmediate()
            serverManager.prepareLogTail(command: config.serveCommand)
        }
        .onChange(of: commandDraft) { _ in
            scheduleBinaryStatusRefresh()
        }
        .onDisappear {
            binaryCheckWorkItem?.cancel()
        }
    }

    private func copyLogTail() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logTailer.lines.joined(separator: "\n"), forType: .string)
    }

    private func save() {
        commandDraft = CommandTokenizer.restoringASCIIHyphens(commandDraft)
        config.serveCommand = commandDraft
        refreshBinaryStatusImmediate()
        serverManager.prepareLogTail(command: config.serveCommand)
    }

    private func saveAndStart() {
        save()
        serverManager.start(command: config.serveCommand)
    }

    private func saveAndRestart() {
        save()
        serverManager.restart(command: config.serveCommand)
    }

    private func openPerformanceAnalysisChat() {
        guard let url = serverManager.chatURL, !isPreparingAnalysis else { return }
        let command = CommandTokenizer.restoringASCIIHyphens(config.serveCommand)
        let logs = logTailer.textSinceSessionStart()
        let tokens = CommandTokenizer.tokenize(command)
        guard let first = tokens.first,
              let binary = SushiBinary.resolve(fromCommandToken: first)
        else {
            let alert = NSAlert()
            alert.messageText = "sushi not found"
            alert.informativeText =
                "Could not resolve the sushi binary from the serve command."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        isPreparingAnalysis = true
        DispatchQueue.global(qos: .userInitiated).async {
            let help = PerformanceAnalysisPrompt.fetchServeHelp(binary: binary)
            let message = PerformanceAnalysisPrompt.message(
                serveCommand: command,
                logs: logs,
                serveHelp: help
            )
            DispatchQueue.main.async {
                isPreparingAnalysis = false
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message, forType: .string)

                let alert = NSAlert()
                alert.messageText = "Analysis prompt copied"
                alert.informativeText =
                    "The prompt is on the clipboard (includes `sushi serve -h`). After chat opens, paste it with ⌘V."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open Chat")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func scheduleBinaryStatusRefresh() {
        binaryCheckWorkItem?.cancel()
        let draft = commandDraft
        let work = DispatchWorkItem {
            let missing = !SushiBinary.isAvailable(command: draft)
            DispatchQueue.main.async {
                self.sushiMissing = missing
            }
        }
        binaryCheckWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func refreshBinaryStatusImmediate() {
        binaryCheckWorkItem?.cancel()
        sushiMissing = !SushiBinary.isAvailable(command: commandDraft)
    }

    private func terminalLabel(_ terminal: PreferredTerminal) -> String {
        if terminal.isInstalled {
            return terminal.displayName
        }
        return "\(terminal.displayName) (not installed)"
    }
}
