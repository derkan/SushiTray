import AppKit

/// A menu button with a trailing browser-link symbol and native button activation.
final class ExternalLinkMenuItemView: NSButton {
    private weak var item: NSMenuItem?
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    private let linkImage = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)

    init(item: NSMenuItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        title = item.title
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(activateLink)
        autoresizingMask = [.width]
        setAccessibilityHelp("Opens in your browser")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovered = false
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let selected = isEnabled && (hovered || item?.isHighlighted == true || cell?.isHighlighted == true)
        if selected {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let color: NSColor = !isEnabled ? .disabledControlTextColor : selected ? .selectedMenuItemTextColor : .labelColor
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: color])
        text.draw(at: NSPoint(x: 14, y: (bounds.height - text.size().height) / 2))
        if let linkImage {
            let icon = NSRect(x: bounds.width - 26, y: (bounds.height - 12) / 2, width: 12, height: 12)
            let tinted = linkImage.withSymbolConfiguration(.init(paletteColors: [color])) ?? linkImage
            tinted.draw(in: icon)
        }
    }

    @objc private func activateLink() {
        guard isEnabled, let item, let menu = item.menu else { return }
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: index)
    }
}
