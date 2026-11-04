import SwiftUI

/// Live server summary and API address hosted inside the native tray menu.
struct ServerStatusCard: View {
    static let width: CGFloat = 320
    static let height: CGFloat = 280

    @State private var copiedURL: URL?
    @State private var copyFeedbackTask: Task<Void, Never>?

    struct Snapshot {
        var running = false
        var ready = false
        var modelState: ModelsClient.LoadState?
        var prefilling = false
        var prefillProgress: Double?
        var decoding = false
        var metricsError: String?
        var model = "No model loaded"
        var apiURL: URL?
        var memoryMB: Double?
        var totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        var decode: Double?
        var prefill: Double?
        var gpuMHz: Double?
        var gpuPercent: Double?
        var history: [DecodePoint] = []
    }

    let snapshot: Snapshot

    private var status: String {
        if snapshot.modelState == .error { return "Load error" }
        if snapshot.running, snapshot.modelState == .loading { return "Loading model" }
        if snapshot.ready {
            if snapshot.decoding { return snapshot.prefilling ? "Decode + Prefill" : "Generating" }
            return snapshot.prefilling ? "Prefilling" : "Running"
        }
        return snapshot.running ? (snapshot.metricsError == nil ? "Starting" : "Connecting") : "Stopped"
    }

    private var statusColor: Color {
        if snapshot.modelState == .error { return .red }
        if snapshot.modelState == .loading { return .orange }
        if snapshot.ready { return snapshot.prefilling ? .orange : snapshot.decoding ? .blue : .green }
        return snapshot.running ? .orange : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Group {
                    if let image = Self.cachedStatusBarImage {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "fish.fill").resizable().scaledToFit()
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                Text("SushiTray").font(.system(size: 12, weight: .semibold))
                Text(UpdateChecker.appVersion)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(status).font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(statusColor.opacity(0.14), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.running ? snapshot.model : "Server stopped")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                    .help(snapshot.model)
                Button(action: copyAPIAddress) {
                    HStack(spacing: 5) {
                        Text(snapshot.apiURL?.absoluteString ?? "API address unavailable")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: copiedURL == snapshot.apiURL && copiedURL != nil ? "checkmark" : "doc.on.doc")
                        if copiedURL != nil, copiedURL == snapshot.apiURL { Text("Copied") }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(copiedURL != nil && copiedURL == snapshot.apiURL ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(snapshot.apiURL == nil)
                .help("Copy OpenAI-compatible API base URL")
                .accessibilityLabel("Copy API address")
                .accessibilityValue(copiedURL != nil && copiedURL == snapshot.apiURL ? "Copied to clipboard" : snapshot.apiURL?.absoluteString ?? "Unavailable")
            }

            HStack(alignment: .top, spacing: 0) {
                metric(snapshot.decode, label: "DECODE", detail: "tok/s", alignment: .leading)
                metric(snapshot.prefill, label: "LAST PREFILL", detail: prefillDetail, alignment: .center)
                    .help("Last completed prefill speed; active progress is shown separately")
                metric(snapshot.gpuMHz, label: "GPU MHz", detail: snapshot.gpuPercent.map { String(format: "%.0f%%", $0) } ?? "—", alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                DecodeSparkline(points: snapshot.history)
                    .frame(height: 28)
                HStack {
                    Text("DECODE · 5 MIN")
                    Spacer()
                    Text("tok/s")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                resourceBar("GPU", value: snapshot.gpuPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                            fraction: snapshot.gpuPercent.map { $0 / 100 }, color: .blue)
                resourceBar("RAM", value: memorySummary, fraction: memoryFraction, color: .purple)
            }
        }
        .padding(14)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .onDisappear {
            copyFeedbackTask?.cancel()
            copiedURL = nil
        }
        .help(snapshot.metricsError ?? "Live Sushi server metrics")
        .accessibilityElement(children: .contain)
    }

    private var prefillDetail: String {
        guard snapshot.prefilling else { return "tok/s" }
        return snapshot.prefillProgress.map { String(format: "tok/s · %.0f%%", $0 * 100) } ?? "tok/s · active"
    }

    private var memoryFraction: Double? {
        guard let mb = snapshot.memoryMB, snapshot.totalMemoryBytes > 0 else { return nil }
        return min(1, max(0, mb * 1_048_576 / Double(snapshot.totalMemoryBytes)))
    }

    private var memorySummary: String {
        guard let mb = snapshot.memoryMB, let fraction = memoryFraction else { return "—" }
        return String(format: "%.0f%% · %.1f/%.0f GiB", fraction * 100, mb / 1024,
                      Double(snapshot.totalMemoryBytes) / 1_073_741_824)
    }

    private func copyAPIAddress() {
        guard let url = snapshot.apiURL else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(url.absoluteString, forType: .string) else { return }
        copiedURL = url
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            copiedURL = nil
        }
    }

    private func resourceBar(_ title: String, value: String, fraction: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Text(value).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(1, max(0, fraction ?? 0)))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func metric(_ value: Double?, label: String, detail: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value.map { String(format: "%.1f", $0) } ?? "unavailable") \(detail)")
    }
    /// Decoded once — never reload PNG from disk on each SwiftUI render.
    private static let cachedStatusBarImage: NSImage? = {
        let candidates: [String?] = [
            Bundle.main.path(forResource: "statusbar", ofType: "png"),
            Bundle.main.path(forResource: "statusbar@2x", ofType: "png"),
            Bundle.main.bundlePath
                + "/Contents/Resources/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png",
            Bundle.main.bundlePath
                + "/Contents/Resources/Assets.xcassets/StatusBarIcon.imageset/statusbar.png",
        ]
        for path in candidates {
            guard let path, let image = NSImage(contentsOfFile: path) else { continue }
            image.isTemplate = false
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        if let named = NSImage(named: "StatusBarIcon") {
            named.isTemplate = false
            return named
        }
        return nil
    }()
}

private struct DecodeSparkline: View {
    let points: [DecodePoint]

    var body: some View {
        GeometryReader { geometry in
            let end = points.last?.time ?? 0
            let maximum = max(1, points.compactMap(\.tokensPerSecond).max() ?? 1)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                Path { path in
                    var connected = false
                    for point in points {
                        guard let rate = point.tokensPerSecond else { connected = false; continue }
                        let x = min(1, max(0, (point.time - end + 300) / 300)) * geometry.size.width
                        let y = (1 - min(1, max(0, rate / maximum))) * (geometry.size.height - 2) + 1
                        let position = CGPoint(x: x, y: y)
                        if connected { path.addLine(to: position) } else { path.move(to: position) }
                        connected = true
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityLabel("Decode speed over the last five minutes")
        .accessibilityValue(points.compactMap(\.tokensPerSecond).max().map { String(format: "Peak %.1f tokens per second", $0) } ?? "No samples")
    }
}
