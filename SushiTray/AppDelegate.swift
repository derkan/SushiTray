import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusBarHosting: NSHostingView<StatusBarView>!
    private var statusCardHosting: NSHostingView<ServerStatusCard>?
    private var settingsWindow: NSWindow?

    private let serverManager = ServerManager.shared
    private let config = AppConfig.shared

    private var modelsMenu = NSMenu(title: "Models")
    private var agentsMenu = NSMenu(title: "Agents")

    private var startStopMenuItem: NSMenuItem!
    private var openChatMenuItem: NSMenuItem!
    private var serverPageItems: [NSMenuItem] = []
    private var modelsMenuItem: NSMenuItem!
    private var agentsMenuItem: NSMenuItem!
    private var displayedModels: [SushiModel] = []
    private var modelsSource: ModelsClient.Source = .disk
    private var modelsError: String?
    private var selectedModelID: String?
    private var isRefreshingModels = false
    private var nextModelsRefresh = Date.distantPast
    private var isStatusMenuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusBar()
        serverManager.onTick = { [weak self] in
            guard let self else { return }
            self.updateMainMenuLabels()
            if self.serverManager.isRunning, Date() >= self.nextModelsRefresh {
                self.refreshModelsAsync()
            }
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
        if config.checkForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.checkForUpdates(interactive: false)
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

    /// Accessory apps have no system Edit menu; without it Cmd/Ctrl C-V never reach text views.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

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

        let card = NSHostingView(rootView: ServerStatusCard(snapshot: .init()))
        card.frame = NSRect(x: 0, y: 0, width: ServerStatusCard.width, height: ServerStatusCard.height)
        let cardItem = NSMenuItem()
        cardItem.view = card
        menu.addItem(cardItem)
        menu.addItem(.separator())
        statusCardHosting = card

        startStopMenuItem = NSMenuItem(
            title: "Start Server",
            action: #selector(toggleServer),
            keyEquivalent: ""
        )
        startStopMenuItem.target = self
        menu.addItem(startStopMenuItem)

        openChatMenuItem = NSMenuItem(
            title: "Chat",
            action: #selector(openChat),
            keyEquivalent: ""
        )
        openChatMenuItem.target = self
        openChatMenuItem.view = ExternalLinkMenuItemView(item: openChatMenuItem)
        openChatMenuItem.isHidden = true
        menu.addItem(openChatMenuItem)

        let dashboardItem = NSMenuItem(title: "Dashboard", action: #selector(openServerPage(_:)), keyEquivalent: "")
        dashboardItem.target = self
        dashboardItem.view = ExternalLinkMenuItemView(item: dashboardItem)
        dashboardItem.representedObject = "/"
        dashboardItem.isEnabled = false
        serverPageItems.append(dashboardItem)
        menu.addItem(dashboardItem)

        modelsMenuItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        modelsMenu.delegate = self
        modelsMenuItem.submenu = modelsMenu
        menu.addItem(modelsMenuItem)

        agentsMenuItem = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
        agentsMenu.delegate = self
        agentsMenuItem.submenu = agentsMenu
        menu.addItem(agentsMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesMenu),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

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
            isStatusMenuOpen = true
            updateMainMenuLabels()
            refreshModelsAsync()
        } else if menu === modelsMenu {
            rebuildModelsMenu()
            refreshModelsAsync()
        } else if menu === agentsMenu {
            rebuildAgentsMenu()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusItem.menu { isStatusMenuOpen = false }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for entry in menu.items where entry.view is ExternalLinkMenuItemView {
            entry.view?.needsDisplay = true
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

    @objc private func openServerPage(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let url = serverManager.pageURL(path: path) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyPackUpdate(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
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

        let conn = serverManager.connection ?? config.connection
        let base = conn.url(path: "")
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

    @objc private func checkForUpdatesMenu() {
        checkForUpdates(interactive: true)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SushiTray"
        alert.informativeText =
            "Menu bar controller for the sushi AI server.\nVersion \(UpdateChecker.appVersion)"
        alert.alertStyle = .informational

        let repoURL = URL(string: "https://github.com/derkan/SushiTray")!
        let linkField = NSTextField(labelWithString: "")
        linkField.isSelectable = true
        linkField.allowsEditingTextAttributes = true
        linkField.attributedStringValue = NSAttributedString(
            string: repoURL.absoluteString,
            attributes: [
                .link: repoURL,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        linkField.sizeToFit()
        alert.accessoryView = linkField

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Checks sushi CLI + SushiTray GitHub releases. When `interactive`, always shows a result alert.
    private func checkForUpdates(interactive: Bool) {
        Task {
            let report = await UpdateChecker.check()
            await MainActor.run {
                self.presentUpdateReport(report, interactive: interactive)
            }
        }
    }

    private func presentUpdateReport(_ report: UpdateChecker.Report, interactive: Bool) {
        if !report.hasAnyUpdate {
            guard interactive else { return }
            let alert = NSAlert()
            alert.messageText = "You’re up to date"
            alert.informativeText = report.summary
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Updates available"
        alert.informativeText = report.summary + "\n\nUpdate now via Homebrew when possible?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            await self.runUpdateFlow(report: report)
        }
    }

    @MainActor
    private func runUpdateFlow(report: UpdateChecker.Report) async {
        let wasRunning = serverManager.isRunning
        let progress = makeUpdateProgressAlert()
        let progressWindow = progress.window
        progressWindow.center()
        progressWindow.level = NSWindow.Level.modalPanel
        NSApp.activate(ignoringOtherApps: true)
        progressWindow.makeKeyAndOrderFront(nil)

        let result = await UpdateChecker.applyUpdates(from: report)

        progressWindow.orderOut(nil)

        var bodyLines = result.summaryLines
        if result.sushiUpdated, wasRunning {
            serverManager.restart(command: config.serveCommand)
            bodyLines.append("Server restarted with the new sushi binary.")
        }

        let done = NSAlert()
        done.messageText = updateResultTitle(result)
        done.informativeText = bodyLines.isEmpty ? "Done." : bodyLines.joined(separator: "\n")
        done.alertStyle = result.hasFailure ? .warning : .informational

        if result.appUpdated {
            done.addButton(withTitle: "Relaunch SushiTray")
            done.addButton(withTitle: "OK")
            let response = done.runModal()
            if response == .alertFirstButtonReturn {
                UpdateChecker.relaunchApp()
            }
        } else {
            done.addButton(withTitle: "OK")
            done.runModal()
        }
    }

    @MainActor
    private func makeUpdateProgressAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Updating…"
        alert.informativeText = "Installing updates. This may take a minute."
        alert.alertStyle = .informational
        let indicator = NSProgressIndicator(
            frame: NSRect(x: 0, y: 0, width: 260, height: 16)
        )
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        alert.accessoryView = indicator
        return alert
    }

    private func updateResultTitle(_ result: UpdateChecker.UpdateResult) -> String {
        if result.hasFailure, result.hasSuccess {
            return "Partially updated"
        }
        if result.hasFailure {
            return "Update failed"
        }
        return "Update complete"
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
        updateStatusCard()
        for item in serverPageItems {
            item.isEnabled = serverManager.isReady
            (item.view as? NSButton)?.isEnabled = item.isEnabled
        }
        startStopMenuItem.title = serverManager.isRunning ? "Stop Server" : "Start Server"
        startStopMenuItem.toolTip = serverManager.errorMessage ?? serverManager.metricsError
        openChatMenuItem.isHidden = !serverManager.isReady
        openChatMenuItem.isEnabled = serverManager.isReady
        (openChatMenuItem.view as? NSButton)?.isEnabled = openChatMenuItem.isEnabled
        openChatMenuItem.toolTip = serverManager.chatURL?.absoluteString
    }

    private func updateStatusCard() {
        guard isStatusMenuOpen else { return }
        let liveModels = modelsSource == .api ? displayedModels : []
        let model = liveModels.first { $0.loaded == true || $0.state == "ready" }
            ?? liveModels.first { $0.state == "loading" }
        let selected = ServeCommandParser.modelPath(from: CommandTokenizer.tokenize(config.serveCommand))
            .map { ($0 as NSString).lastPathComponent }
        var snapshot = ServerStatusCard.Snapshot()
        snapshot.running = serverManager.isRunning
        snapshot.ready = serverManager.isReady
        snapshot.modelState = serverManager.errorMessage == nil ? serverManager.modelState : .error
        snapshot.prefilling = serverManager.isPrefilling
        snapshot.prefillProgress = serverManager.prefillProgress
        snapshot.decoding = serverManager.isDecoding
        snapshot.metricsError = serverManager.errorMessage ?? serverManager.metricsError
        snapshot.model = model.map { $0.id + ($0.state == "loading" ? " · Loading" : "") }
            ?? (serverManager.isReady ? "No model loaded" : selected ?? "Loading server…")
        snapshot.apiURL = (serverManager.connection ?? config.connection).url(path: "/v1")
        snapshot.memoryMB = serverManager.serverMemoryMB
        snapshot.decode = serverManager.genTokensPerSecond
        snapshot.prefill = serverManager.prefillTokensPerSecond
        snapshot.gpuMHz = serverManager.gpuClockMHz
        snapshot.gpuPercent = serverManager.gpuUtilization.map { $0 * 100 }
        snapshot.history = serverManager.isRunning ? serverManager.decodeHistory : []
        statusCardHosting?.rootView = ServerStatusCard(snapshot: snapshot)
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
            if let update = model.packUpdate, !update.latest.isEmpty, !update.command.isEmpty {
                let copy = NSMenuItem(
                    title: "Pack \(update.latest) available — copy update command",
                    action: #selector(copyPackUpdate(_:)), keyEquivalent: ""
                )
                copy.target = self
                copy.representedObject = update.command
                copy.toolTip = "Installed: \(update.current). \(update.command)"
                copy.indentationLevel = 1
                modelsMenu.addItem(copy)
            }
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

    // MARK: - Models refresh

    private func refreshModelsAsync() {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        let modelPending = serverManager.isRunning && (serverManager.modelState == nil || serverManager.modelState == .loading)
        nextModelsRefresh = Date().addingTimeInterval(modelPending ? 1 : 5)
        let running = serverManager.isRunning
        let sessionID = serverManager.sessionIdentifier
        let connection = serverManager.connection ?? config.connection
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
                self.isRefreshingModels = false
                guard self.serverManager.sessionIdentifier == sessionID,
                      self.serverManager.isRunning == running,
                      (self.serverManager.connection ?? self.config.connection) == connection else { return }
                let changed = self.displayedModels != result.models
                    || self.modelsSource != result.source || self.modelsError != result.errorMessage
                self.displayedModels = result.models
                self.modelsSource = result.source
                self.modelsError = result.errorMessage
                if result.source == .api {
                    self.serverManager.updateModelState(models: result.models)
                    if result.models != cached { self.config.saveCachedModels(result.models) }
                }
                if changed { self.rebuildModelsMenu() }
                self.updateStatusCard()
            }
        }
    }

    private func updateSelectedModelFromCommand() {
        let tokens = CommandTokenizer.tokenize(config.serveCommand)
        if let path = ServeCommandParser.modelPath(from: tokens) {
            selectedModelID = (path as NSString).lastPathComponent
        }
    }

}
