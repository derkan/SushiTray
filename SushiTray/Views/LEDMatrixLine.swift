import SwiftUI
import AppKit
import QuartzCore

/// Native cached bitmaps with compositor-driven effects: no per-frame SwiftUI/Canvas work.
struct LEDMatrixLine: NSViewRepresentable {
    private static let cells = 12
    private static let nativeFont = NSFont(name: "Menlo-Regular", size: 8.5)
        ?? NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
    private static let cellWidth = ("0" as NSString).size(withAttributes: [.font: nativeFont]).width
    static let width = ceil(CGFloat(cells) * cellWidth)
    static let height: CGFloat = 11
    private static let progressStart = 3 * cellWidth
    private static let grid: CGPath = {
        let path = CGMutablePath()
        let pitch = (cellWidth - 0.7) / 5
        for cell in 0..<cells {
            for row in 0..<7 {
                for column in 0..<5 {
                    let rect = CGRect(x: CGFloat(cell) * cellWidth + 0.35 + CGFloat(column) * pitch,
                                      y: (height - 6.65) / 2 + CGFloat(row), width: pitch * 0.7, height: 0.65)
                    path.addRoundedRect(in: rect, cornerWidth: 0.12, cornerHeight: 0.12)
                }
            }
        }
        return path
    }()

    let text: String
    let color: Color
    var progress: Double? = nil
    var shimmering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> DisplayView { DisplayView(frame: .init(x: 0, y: 0, width: Self.width, height: Self.height)) }

    func updateNSView(_ view: DisplayView, context: Context) {
        view.update(text: text, color: NSColor(color), progress: progress,
                    shimmering: shimmering && !reduceMotion)
    }

    static func dismantleNSView(_ view: DisplayView, coordinator: ()) { view.stopAnimations() }

    final class DisplayView: NSView {
        private let gridLayer = CALayer()
        private let progressLayer = CALayer()
        private let progressMask = CALayer()
        private let textLayer = CALayer()
        private let shineLayer = CALayer()
        private let shineMask = CALayer()
        private let gradient = CAGradientLayer()
        private var currentText = ""
        private var currentColor: NSColor?
        private var currentProgress: Double?
        private var currentScale: CGFloat = 0
        private var shimmering = false
        private static var grids: [CGFloat: CGImage] = [:]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            for item in [gridLayer, progressLayer, textLayer, shineLayer] {
                item.frame = bounds
                item.contentsGravity = .resize
                layer?.addSublayer(item)
            }
            gridLayer.opacity = 0.085
            progressLayer.mask = progressMask
            progressMask.backgroundColor = NSColor.white.cgColor
            shineLayer.mask = shineMask
            shineMask.frame = bounds
            gradient.frame = CGRect(x: -24, y: 0, width: 24, height: LEDMatrixLine.height)
            gradient.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            shineLayer.addSublayer(gradient)
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            if let currentColor {
                update(text: currentText, color: currentColor, progress: currentProgress, shimmering: shimmering)
            }
        }

        override var intrinsicContentSize: NSSize { NSSize(width: LEDMatrixLine.width, height: LEDMatrixLine.height) }

        func update(text: String, color: NSColor, progress: Double?, shimmering: Bool) {
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let changed = text != currentText || currentColor?.isEqual(color) != true || scale != currentScale || self.shimmering != shimmering
            self.shimmering = shimmering
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if changed {
                currentText = text
                currentColor = color
                currentScale = scale
                if Self.grids[scale] == nil {
                    Self.grids[scale] = bitmap(scale: scale) { context in
                        context.addPath(LEDMatrixLine.grid)
                        context.setFillColor(NSColor.white.cgColor)
                        context.fillPath()
                    }
                }
                gridLayer.contents = Self.grids[scale]
                progressLayer.contents = bitmap(scale: scale) { context in
                    context.addPath(LEDMatrixLine.grid)
                    context.setFillColor(color.cgColor)
                    context.fillPath()
                }
                let textColor = shimmering ? color.withAlphaComponent(color.alphaComponent * 0.75) : color
                textLayer.contents = textBitmap(text, color: textColor, scale: scale)
                shineMask.contents = textBitmap(text, color: .white, scale: scale, valueOnly: true)
                for item in [gridLayer, progressLayer, textLayer, shineMask] { item.contentsScale = scale }
                setAccessibilityLabel(text)
            }
            if changed || currentProgress != progress {
                currentProgress = progress
                progressLayer.isHidden = progress == nil
                progressLayer.opacity = 0.8
                progressMask.frame = CGRect(x: LEDMatrixLine.progressStart, y: 0,
                    width: CGFloat(LEDMatrixLine.cells - 3) * LEDMatrixLine.cellWidth * min(1, max(0, progress ?? 0)),
                    height: LEDMatrixLine.height)
            }
            shineLayer.isHidden = !shimmering
            CATransaction.commit()
            updateAnimations()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateAnimations()
        }

        private func updateAnimations() {
            if window != nil && shimmering {
                if gradient.animation(forKey: "shine") == nil {
                    let animation = CABasicAnimation(keyPath: "position.x")
                    animation.fromValue = -12
                    animation.toValue = LEDMatrixLine.width + 12
                    animation.duration = 2.6
                    animation.repeatCount = .infinity
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    gradient.add(animation, forKey: "shine")
                }
            } else { gradient.removeAnimation(forKey: "shine") }
        }

        func stopAnimations() {
            gradient.removeAllAnimations()
        }

        private func textBitmap(_ text: String, color: NSColor, scale: CGFloat, valueOnly: Bool = false) -> CGImage? {
            bitmap(scale: scale) { context in
                if valueOnly {
                    context.clip(to: CGRect(x: LEDMatrixLine.progressStart, y: 0,
                                           width: LEDMatrixLine.width - LEDMatrixLine.progressStart, height: LEDMatrixLine.height))
                }
                let value = NSAttributedString(string: String(text.uppercased().prefix(LEDMatrixLine.cells)),
                    attributes: [.font: LEDMatrixLine.nativeFont, .foregroundColor: color, .kern: 0])
                value.draw(at: NSPoint(x: 0, y: (LEDMatrixLine.height - value.size().height) / 2))
            }
        }

        private func bitmap(scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(LEDMatrixLine.width * scale)), pixelsHigh: Int(ceil(LEDMatrixLine.height * scale)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: scale, y: scale)
            draw(context.cgContext)
            return bitmap.cgImage
        }
    }
}
