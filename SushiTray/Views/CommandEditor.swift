import AppKit
import SwiftUI

/// Monospaced command editor without macOS smart dashes/quotes (`--` must stay `--`).
struct CommandEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        disableSmartSubstitutions(textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        disableSmartSubstitutions(textView)
        context.coordinator.text = $text
        if textView.string != text {
            textView.string = text
        }
    }

    private func disableSmartSubstitutions(_ textView: NSTextView) {
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.enabledTextCheckingTypes = 0
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Handles copy/paste when SwiftUI swallows menu key equivalents, including Control+C/V/P.
private final class CommandTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let command = mods.contains(.command) && !mods.contains(.option)
        let control = mods.contains(.control) && !mods.contains(.command) && !mods.contains(.option)
        guard command || control else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "p" where control:
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "a" where command:
            selectAll(nil)
            return true
        case "z" where command:
            if mods.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
