import SwiftUI
import AppKit

struct StatusBarView: View {
    @ObservedObject var serverManager: ServerManager

    private let ink = Color.white.opacity(0.95)
    private let inkMuted = Color.white.opacity(0.55)

    private var isRunning: Bool { serverManager.isRunning }

    var body: some View {
        HStack(spacing: 5) {
            MetricBar(
                label: "GPU",
                fraction: isRunning ? (serverManager.gpuUtilization ?? 0) : 0,
                muted: !isRunning,
                ink: ink,
                inkMuted: inkMuted
            )
            MetricBar(
                label: "MEM",
                fraction: isRunning ? (serverManager.gpuMemoryFraction ?? 0) : 0,
                muted: !isRunning,
                ink: ink,
                inkMuted: inkMuted
            )
            VStack(alignment: .leading, spacing: 0) {
                RateLine(
                    prefix: "P",
                    value: isRunning ? serverManager.prefillTokensPerSecond : nil,
                    muted: !isRunning,
                    ink: ink,
                    inkMuted: inkMuted
                )
                RateLine(
                    prefix: "T",
                    value: isRunning ? serverManager.genTokensPerSecond : nil,
                    muted: !isRunning,
                    ink: ink,
                    inkMuted: inkMuted
                )
            }

            appGlyph
        }
        .fixedSize()
    }

    private var appGlyph: some View {
        Group {
            if let image = Self.cachedStatusBarImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "fish")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ink)
                    .frame(width: 16, height: 16)
            }
        }
        .overlay(alignment: .bottom) {
            Circle()
                .fill(isRunning ? Color.green : Color.gray.opacity(0.7))
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                )
                .offset(y: 1)
        }
        .accessibilityLabel("SushiTray")
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

private struct MetricBar: View {
    let label: String
    let fraction: Double
    let muted: Bool
    let ink: Color
    let inkMuted: Color

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
        .help("\(label): \(Int((fraction * 100).rounded()))%")
    }
}

private struct RateLine: View {
    let prefix: String
    let value: Double?
    let muted: Bool
    let ink: Color
    let inkMuted: Color

    var body: some View {
        Text(formatted)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(muted || value == nil ? inkMuted : ink)
            .lineLimit(1)
    }

    private var formatted: String {
        if let value {
            if value >= 10 {
                return String(format: "%@: %.0ftk/s", prefix, value)
            }
            return String(format: "%@: %.1ftk/s", prefix, value)
        }
        return "\(prefix): —"
    }
}
