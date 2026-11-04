import SwiftUI
import AppKit

private enum TrayMetricsLayout {
    static let columnWidth = LEDMatrixLine.width
}

struct StatusBarView: View {
    @ObservedObject var serverManager: ServerManager

    private let ink = Color.white.opacity(0.95)
    private let inkMuted = Color.white.opacity(0.55)

    private var isRunning: Bool { serverManager.isRunning }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                MetricBar(
                    label: "GPU",
                    fraction: isRunning ? (serverManager.gpuUtilization ?? 0) : 0,
                    muted: !isRunning,
                    ink: ink,
                    inkMuted: inkMuted
                )
                MetricBar(
                    label: "MEM",
                    fraction: isRunning ? (serverManager.serverMemoryFraction ?? 0) : 0,
                    muted: !isRunning || serverManager.serverMemoryFraction == nil,
                    ink: ink,
                    inkMuted: inkMuted
                )
                MetricBar(
                    label: "CTX",
                    fraction: isRunning ? (serverManager.contextUsage?.fraction ?? 0) : 0,
                    muted: !isRunning || serverManager.contextUsage == nil,
                    ink: ink,
                    inkMuted: inkMuted,
                    detail: contextDescription
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                if let state = displayedModelState {
                    ModelStateLine(state: state)
                } else if isRunning, serverManager.isPrefilling {
                    PrefillProgressView(
                        fraction: serverManager.prefillProgress,
                        lastRate: serverManager.prefillTokensPerSecond,
                        ink: ink
                    )
                } else if isRunning, serverManager.prefillTokensPerSecond != nil {
                    RateLine(
                        prefix: "P",
                        value: serverManager.prefillTokensPerSecond,
                        muted: false,
                        ink: ink,
                        inkMuted: inkMuted
                    )
                } else {
                    ModelStateLine(state: .ready)
                }
                if displayedModelState == .loading {
                    LEDMatrixLine(text: "SushiTray", color: ink)
                        .help("SushiTray · loading model")
                } else {
                    RateLine(
                        prefix: "T",
                        value: isRunning ? serverManager.genTokensPerSecond : nil,
                        muted: !isRunning,
                        ink: ink,
                        inkMuted: inkMuted
                    )
                }
            }
            .frame(width: TrayMetricsLayout.columnWidth, height: 22, alignment: .leading)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SushiTray")
    }

    private var contextDescription: String {
        if let context = serverManager.contextUsage, isRunning {
            return String(format: "CTX: %.0f%%", context.fraction * 100)
                + " · \(context.usedTokens.formatted()) / \(context.limitTokens.formatted()) tokens"
        }
        if serverManager.activeSessionCount > 1 {
            return "CTX unavailable: \(serverManager.activeSessionCount) active sessions"
        }
        return serverManager.activeSessionCount == 1 ? "CTX: session limit unavailable" : "CTX: no active session"
    }

    private var displayedModelState: ModelsClient.LoadState? {
        if serverManager.errorMessage != nil { return .error }
        guard isRunning else { return .unloaded }
        // Live inference proves the model is usable even if the model-list poll is behind.
        if serverManager.isPrefilling || serverManager.isDecoding { return nil }
        guard let state = serverManager.modelState else { return .loading }
        if state == .loading || state == .error { return state }
        return serverManager.prefillTokensPerSecond == nil ? state : nil
    }

    /// Decoded once — never reload PNG from disk on each SwiftUI render.
    static let cachedStatusBarImage: NSImage? = {
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

private struct MetricBar: View {
    let label: String
    let fraction: Double
    let muted: Bool
    let ink: Color
    let inkMuted: Color
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            VStack(spacing: -1) {
                ForEach(Array(label.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(muted ? inkMuted : ink)
                }
            }
            .frame(width: 8)

            GeometryReader { geo in
                let h = geo.size.height
                let fill = max(0, min(1, fraction)) * h
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ink.opacity(muted ? 0.2 : 0.28))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ink.opacity(muted ? 0.45 : 0.95))
                        .frame(height: max(fill, fraction > 0 ? 2 : 0))
                }
            }
            .frame(width: 7, height: 14)
        }
        .frame(height: 16)
        .help(detail ?? "\(label): \(Int((fraction * 100).rounded()))%")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detail ?? "\(Int((fraction * 100).rounded())) percent")
    }
}

private struct RateLine: View {
    let prefix: String
    let value: Double?
    let muted: Bool
    let ink: Color
    let inkMuted: Color

    var body: some View {
        LEDMatrixLine(text: "\(prefix): \(formatted)", color: muted || value == nil ? inkMuted : ink)
    }

    private var formatted: String {
        if let value {
            if value >= 1_000_000 { return String(format: "%.1fM t/s", value / 1_000_000) }
            if value >= 100_000 { return String(format: "%.0fk t/s", value / 1_000) }
            if value >= 10 {
                return String(format: "%.0f t/s", value)
            }
            return String(format: "%.1f t/s", value)
        }
        return "… t/s"
    }
}

/// Progress lights the same matrix cells used by status text and rates.
struct PrefillProgressView: View {
    let fraction: Double?
    var lastRate: Double? = nil
    let ink: Color

    var body: some View {
        LEDMatrixLine(text: fraction == nil ? "P: prefill.." : "P:", color: ink,
                      progress: fraction, pulsing: fraction == nil)
            .help(progressDescription)
            .accessibilityLabel("Prefill")
            .accessibilityValue(progressDescription)
    }

    private var progressDescription: String {
        let progress = fraction.map { String(format: "Prefill: %.0f%% of uncached prompt tokens processed", $0 * 100) }
            ?? "Prefill in progress; target not yet available"
        return progress + (lastRate.map { String(format: " · Last prefill: %.1f tok/s", $0) } ?? "")
    }
}

struct ModelStateLine: View {
    let state: ModelsClient.LoadState

    private var color: Color {
        switch state {
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        case .unloaded: return .white.opacity(0.55)
        }
    }

    private var label: String { state == .unloaded ? "idle" : state.rawValue }

    var body: some View {
        LEDMatrixLine(text: "S: \(label)", color: color, shimmering: state == .loading)
            .help("Model status: \(label)")
            .accessibilityLabel("Model status")
            .accessibilityValue(label)
    }
}
