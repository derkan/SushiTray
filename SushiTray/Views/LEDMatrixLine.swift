import SwiftUI
import AppKit

/// Twelve fixed cells measured from a narrow native monospace font.
struct LEDMatrixLine: View {
    private static let cells = 12
    private static let nativeFont = NSFont(name: "Menlo-Regular", size: 8.5)
        ?? NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
    private static let cellWidth = ("0" as NSString).size(withAttributes: [.font: nativeFont]).width
    static let width = ceil(CGFloat(cells) * cellWidth)
    static let height: CGFloat = 11
    private static let displayFont = Font.custom(nativeFont.fontName, fixedSize: nativeFont.pointSize)

    let text: String
    let color: Color
    var progress: Double? = nil
    var pulsing = false
    var shimmering = false
    @State private var animationStartedAt = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if (pulsing || shimmering), !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
                    let sweepPhase = max(0, context.date.timeIntervalSince(animationStartedAt)).truncatingRemainder(dividingBy: 2.6)
                    let sweep = sweepPhase < 1.8 ? (1 - cos(sweepPhase / 1.8 * .pi)) / 2 : nil
                    matrix(brightness: pulsing ? 0.7 + 0.3 * (1 - cos(phase * .pi)) / 2 : 1,
                           shimmerPosition: shimmering ? sweep : nil)
                }
            } else {
                matrix(brightness: 1)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func matrix(brightness: Double, shimmerPosition: Double? = nil) -> some View {
        let characters = Array(text.uppercased().prefix(Self.cells))
        return Canvas { context, size in
            let yInset = (size.height - 6.65) / 2
            let gridPitch = (Self.cellWidth - 0.7) / 5
            let dotWidth = gridPitch * 0.7
            let progressStart = 3 * Self.cellWidth
            let fillWidth = CGFloat(Self.cells - 3) * Self.cellWidth * min(1, max(0, progress ?? 0))
            var dimDots = Path()
            var progressDots = Path()
            for cell in 0..<Self.cells {
                let origin = CGFloat(cell) * Self.cellWidth
                for row in 0..<7 {
                    for column in 0..<5 {
                        let x = origin + 0.35 + CGFloat(column) * gridPitch
                        let rect = CGRect(x: x, y: yInset + CGFloat(row), width: dotWidth, height: 0.65)
                        let dot = Path(roundedRect: rect, cornerRadius: 0.12)
                        if progress != nil && cell >= 3 && x - progressStart < fillWidth {
                            progressDots.addPath(dot)
                        } else {
                            dimDots.addPath(dot)
                        }
                    }
                }
            }
            context.fill(dimDots, with: .color(.white.opacity(0.085)))
            context.fill(progressDots, with: .color(color.opacity(brightness * 0.8)))

            for (cell, character) in characters.enumerated() where character != " " {
                let rect = CGRect(x: CGFloat(cell) * Self.cellWidth, y: 0, width: Self.cellWidth, height: size.height)
                var glyphContext = context
                glyphContext.clip(to: Path(rect))
                var glyph = glyphContext.resolve(Text(String(character)).font(Self.displayFont))
                glyph.shading = .color(color.opacity(brightness))
                if let shimmerPosition, cell >= 3 {
                    let radius: CGFloat = 12
                    let textEnd = CGFloat(characters.count) * Self.cellWidth
                    let center = progressStart - radius + shimmerPosition * (textEnd - progressStart + 2 * radius)
                    glyph.shading = .linearGradient(
                        Gradient(stops: [
                            .init(color: color, location: 0),
                            .init(color: color, location: 0.15),
                            .init(color: .white, location: 0.5),
                            .init(color: color, location: 0.85),
                            .init(color: color, location: 1)
                        ]),
                        startPoint: CGPoint(x: center - radius, y: 0),
                        endPoint: CGPoint(x: center + radius, y: 0)
                    )
                }
                glyphContext.draw(glyph, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
    }
}
