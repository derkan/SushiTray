import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusBarHosting: NSHostingView<StatusBarView>!
    private var settingsWindow: NSWindow?

    private let serverManager = ServerManager.shared
    private let config = AppConfig.shared

    private var modelsMenu = NSMenu(title: "Models")
    private var agentsMenu = NSMenu(title: "Agents")
    private var systemStatsMenu = NSMenu(title: "System Stats")
    private var servingStatsMenu = NSMenu(title: "Serving Stats")

    private var statusMenuItem: NSMenuItem!
    private var startStopMenuItem: NSMenuItem!
    private var openChatMenuItem: NSMenuItem!
    private var modelsMenuItem: NSMenuItem!
    private var agentsMenuItem: NSMenuItem!
    private var displayedModels: [SushiModel] = []
    private var modelsSource: ModelsClient.Source = .disk
    private var modelsError: String?
    private var selectedModelID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        serverManager.onTick = { [weak self] in
            self?.updateMainMenuLabels()
        }
        serverManager.prepareLogTail(command: config.serveCommand)
        serverManager.startTicking()
        updateSelectedModelFromCommand()
        refreshModelsAsync()
        updateMainMenuLabels()
        if config.autoStartServer {
            serverManager.start(command: config.serveCommand)
            updateMainMenuLabels()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refreshModelsAsync()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        serverManager.stopTicking()
        serverManager.stopSynchronously()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverManager.stopSynchronously()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.toolTip = "SushiTray"

        statusBarHosting = NSHostingView(rootView: StatusBarView(serverManager: serverManager))
        statusBarHosting.appearance = NSAppearance(named: .darkAqua)
        button.addSubview(statusBarHosting)
        pinStatusBarHosting(statusBarHosting, to: button)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        statusMenuItem = NSMenuItem(
            title: "Server: stopped",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        startStopMenuItem = NSMenuItem(
            title: "Start Server",
            action: #selector(toggleServer),
            keyEquivalent: ""
        )
        startStopMenuItem.target = self
        menu.addItem(startStopMenuItem)

        openChatMenuItem = NSMenuItem(
            title: "Open chat",
            action: #selector(openChat),
            keyEquivalent: ""
        )
        openChatMenuItem.target = self
        openChatMenuItem.isHidden = true
        menu.addItem(openChatMenuItem)

        modelsMenuItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        modelsMenu.delegate = self
        modelsMenuItem.submenu = modelsMenu
        menu.addItem(modelsMenuItem)

        agentsMenuItem = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
        agentsMenu.delegate = self
        agentsMenuItem.submenu = agentsMenu
        menu.addItem(agentsMenuItem)

        let systemItem = NSMenuItem(title: "System Stats", action: nil, keyEquivalent: "")
        systemStatsMenu.delegate = self
        systemItem.submenu = systemStatsMenu
        menu.addItem(systemItem)

        let servingItem = NSMenuItem(title: "Serving Stats", action: nil, keyEquivalent: "")
        servingStatsMenu.delegate = self
        servingItem.submenu = servingStatsMenu
        menu.addItem(servingItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About SushiTray",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit SushiTray",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMainMenuLabels()
    }

    private func pinStatusBarHosting(_ hosting: NSView, to button: NSStatusBarButton) {
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu {
            updateMainMenuLabels()
            refreshModelsAsync()
        } else if menu === modelsMenu {
            rebuildModelsMenu()
            refreshModelsAsync()
        } else if menu === agentsMenu {
            rebuildAgentsMenu()
        } else if menu === systemStatsMenu {
            rebuildSystemStatsMenu()
        } else if menu === servingStatsMenu {
            rebuildServingStatsMenu()
        }
    }

    // MARK: - Actions

    @objc private func toggleServer() {
        if serverManager.isRunning {
            serverManager.stop { [weak self] in
                self?.updateMainMenuLabels()
            }
        } else {
            serverManager.start(command: config.serveCommand)
            updateMainMenuLabels()
            // Refresh models shortly after start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refreshModelsAsync()
            }
        }
    }

    @objc private func openChat() {
        guard let url = serverManager.chatURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func launchAgent(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? String else { return }
        let tokens = CommandTokenizer.tokenize(config.serveCommand)
        guard let first = tokens.first,
              let binary = SushiBinary.resolve(fromCommandToken: first)
        else {
            let alert = NSAlert()
            alert.messageText = "sushi not found"
            alert.informativeText = "Install with: brew install beamivalice/tap/sushi"
            alert.runModal()
            return
        }

        let workingDirectory = AgentLauncher.chooseWorkingDirectory(
            agent: agent,
            startingDirectory: config.lastAgentWorkingDirectory
        )
        config.lastAgentWorkingDirectory = workingDirectory

        let conn = config.connection
        let base = URL(string: "http://\(conn.host):\(conn.port)")
            ?? URL(string: "http://127.0.0.1:12345")!
        var modelID: String?
        if let path = ServeCommandParser.modelPath(from: tokens) {
            modelID = (path as NSString).lastPathComponent
        }

        var terminal = config.preferredTerminal
        if !terminal.isInstalled {
            terminal = PreferredTerminal.default
        }

        AgentLauncher.launch(
            agent: agent,
            sushiBinary: binary,
            baseURL: base,
            modelID: modelID,
            workingDirectory: workingDirectory,
            terminal: terminal
        )
    }

    @objc private func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(config: config, serverManager: serverManager)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "SushiTray Settings"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SushiTray"
        alert.informativeText =
            "Menu bar controller for the sushi AI server.\n\nhttps://github.com/beamivalice/sushi"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        selectedModelID = id
        let path = ModelDiscovery.path(forModelID: id, command: config.serveCommand)
        config.setModel(path)
        rebuildModelsMenu()
    }

    // MARK: - Menu builders

    private func updateMainMenuLabels() {
        if serverManager.isRunning {
            statusMenuItem.title = "Server: running (port \(serverManager.port))"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemGreen,
                .font: NSFont.menuFont(ofSize: 0),
            ]
            statusMenuItem.attributedTitle = NSAttributedString(
                string: statusMenuItem.title,
                attributes: attrs
            )
            startStopMenuItem.title = "Stop Server"
            let hasChat = serverManager.chatURL != nil
            openChatMenuItem.isHidden = !hasChat
            openChatMenuItem.isEnabled = hasChat
            if let url = serverManager.chatURL {
                openChatMenuItem.toolTip = url.absoluteString
            } else {
                openChatMenuItem.toolTip = nil
            }
        } else {
            statusMenuItem.attributedTitle = nil
            statusMenuItem.title = "Server: stopped"
            startStopMenuItem.title = "Start Server"
            openChatMenuItem.isHidden = true
            openChatMenuItem.isEnabled = false
            openChatMenuItem.toolTip = nil
        }
        if let err = serverManager.errorMessage, !serverManager.isRunning {
            statusMenuItem.title = "Server: error"
            statusMenuItem.toolTip = err
        } else {
            statusMenuItem.toolTip = nil
        }
    }

    private func rebuildModelsMenu() {
        modelsMenu.removeAllItems()

        if let err = modelsError {
            let note = NSMenuItem(title: "(\(err))", action: nil, keyEquivalent: "")
            note.isEnabled = false
            modelsMenu.addItem(note)
        }

        if modelsSource == .disk {
            let note = NSMenuItem(title: "(from disk)", action: nil, keyEquivalent: "")
            note.isEnabled = false
            modelsMenu.addItem(note)
        } else if modelsSource == .cache {
            let note = NSMenuItem(title: "(cached)", action: nil, keyEquivalent: "")
            note.isEnabled = false
            modelsMenu.addItem(note)
        }

        if displayedModels.isEmpty {
            let empty = NSMenuItem(
                title: "(no models yet — start server)",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            modelsMenu.addItem(empty)
            return
        }

        for model in displayedModels {
            var title = model.displayName
            if model.loaded == true || model.state == "ready" {
                title += " • loaded"
            }
            let item = NSMenuItem(
                title: title,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.id
            if model.id == selectedModelID
                || config.serveCommand.contains(model.id)
            {
                item.state = .on
            }
            modelsMenu.addItem(item)
        }
    }

    private func rebuildAgentsMenu() {
        agentsMenu.removeAllItems()

        let tokens = CommandTokenizer.tokenize(config.serveCommand)
        let binary = tokens.first.flatMap { SushiBinary.resolve(fromCommandToken: $0) }
        let agents = AgentsCatalog.list(sushiBinary: binary)

        if binary == nil {
            let note = NSMenuItem(
                title: "(sushi not found)",
                action: nil,
                keyEquivalent: ""
            )
            note.isEnabled = false
            agentsMenu.addItem(note)
            return
        }

        if !serverManager.isRunning {
            let note = NSMenuItem(
                title: "(start server to connect)",
                action: nil,
                keyEquivalent: ""
            )
            note.isEnabled = false
            agentsMenu.addItem(note)
        }

        for agent in agents {
            let item = NSMenuItem(
                title: agent,
                action: #selector(launchAgent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = agent
            item.isEnabled = binary != nil
            item.toolTip = "sushi launch \(agent)"
            agentsMenu.addItem(item)
        }
    }

    private func rebuildSystemStatsMenu() {
        systemStatsMenu.removeAllItems()
        let mem = MemoryMetricsSampler.sample()
        let gpu = GPUMetricsSampler.sample()

        func add(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            systemStatsMenu.addItem(item)
        }

        if let cpu = mem.cpuFraction {
            add(String(format: "CPU  %.0f%%", cpu * 100))
        } else {
            add("CPU  —")
        }

        if let gpu {
            add(String(format: "GPU  %.0f%%", gpu.utilization * 100))
            add(
                String(
                    format: "GPU memory  %@",
                    byteString(gpu.memoryUsedBytes)
                )
            )
        } else {
            add("GPU  —")
            add("GPU memory  —")
        }

        add(
            String(
                format: "Memory  %@ / %@  (%.0f%%)",
                byteString(mem.usedBytes),
                byteString(mem.totalBytes),
                mem.usedFraction * 100
            )
        )
    }

    private func rebuildServingStatsMenu() {
        servingStatsMenu.removeAllItems()

        func add(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            servingStatsMenu.addItem(item)
        }

        let header = NSMenuItem(title: "Session", action: nil, keyEquivalent: "")
        header.isEnabled = false
        servingStatsMenu.addItem(header)

        add("Requests: \(serverManager.sessionRequests)")
        add("Prompt tokens: \(formatCount(serverManager.sessionPromptTokens))")
        add("Generated tokens: \(formatCount(serverManager.sessionGeneratedTokens))")

        if let p = serverManager.sessionPrefill ?? serverManager.prefillTokensPerSecond {
            add(String(format: "Prefill: %.1f tok/s", p))
        } else {
            add("Prefill: —")
        }
        if let d = serverManager.sessionDecode ?? serverManager.genTokensPerSecond {
            add(String(format: "Decode: %.1f tok/s", d))
        } else {
            add("Decode: —")
        }
    }

    // MARK: - Models refresh

    private func refreshModelsAsync() {
        let running = serverManager.isRunning
        let connection = config.connection
        let command = config.serveCommand
        let cached = config.loadCachedModels()

        Task {
            let result = await ModelsClient.resolve(
                isRunning: running,
                connection: connection,
                command: command,
                cached: cached
            )
            await MainActor.run {
                self.displayedModels = result.models
                self.modelsSource = result.source
                self.modelsError = result.errorMessage
                if result.source == .api {
                    self.config.saveCachedModels(result.models)
                }
                self.rebuildModelsMenu()
            }
        }
    }

    private func updateSelectedModelFromCommand() {
        let tokens = CommandTokenizer.tokenize(config.serveCommand)
        if let path = ServeCommandParser.modelPath(from: tokens) {
            selectedModelID = (path as NSString).lastPathComponent
        }
    }

    // MARK: - Formatting

    private func byteString(_ bytes: UInt64) -> String {
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

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        }
        if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
