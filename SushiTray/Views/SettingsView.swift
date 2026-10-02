import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var logTailer: LogTailer
    @State private var commandDraft: String = ""
    @State private var sushiMissing = false

    init(config: AppConfig, serverManager: ServerManager) {
        self.config = config
        self.serverManager = serverManager
        self.logTailer = serverManager.logTailer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serve Command")
                .font(.headline)

            TextEditor(text: $commandDraft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )

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

            Link(
                "Sushi documentation on GitHub",
                destination: URL(string: "https://github.com/beamivalice/sushi")!
            )
            .font(.callout)

            HStack {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                Button("Reset to Default") {
                    commandDraft = AppConfig.defaultCommand
                }
                Spacer()
                if serverManager.isRunning {
                    Text("Server running — restart to apply command changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Log Tail")
                .font(.headline)
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
                .onChange(of: logTailer.lines.count) { _ in
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            commandDraft = config.serveCommand
            refreshBinaryStatus()
            serverManager.prepareLogTail(command: config.serveCommand)
        }
        .onChange(of: commandDraft) { _ in
            refreshBinaryStatus()
        }
    }

    private func save() {
        config.serveCommand = commandDraft
        refreshBinaryStatus()
        serverManager.prepareLogTail(command: config.serveCommand)
    }

    private func refreshBinaryStatus() {
        sushiMissing = !SushiBinary.isAvailable(command: commandDraft)
    }
}
