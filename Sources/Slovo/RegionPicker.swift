import AppKit

/// A crosshair over every screen to drag out a rectangle, like ⇧⌘4, but it reports where the
/// rectangle is, which `screencapture -i` doesn't. Esc or a click without dragging cancels.
final class RegionPicker {
    private var windows: [PickerPanel] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    /// The rectangle in AppKit screen coordinates, nil when cancelled.
    func pick() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                let panel = PickerPanel(screen: screen) { [weak self] rect in self?.finish(rect) }
                windows.append(panel)
                panel.orderFrontRegardless()
            }
            // The panel under the pointer takes the keyboard, for Esc.
            let mouse = NSEvent.mouseLocation
            (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
        }
    }

    private func finish(_ rect: CGRect?) {
        for window in windows { window.orderOut(nil) }
        windows = []
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

private final class PickerPanel: NSPanel {
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = PickerView(onFinish: onFinish)
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    private let onFinish: (CGRect?) -> Void
    private var start: CGPoint?
    private var current: CGPoint?

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 8, selection.height >= 8, let window else {
            onFinish(nil)
            return
        }
        onFinish(window.convertToScreen(convert(selection, to: nil)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    /// A light dim shows the mode is on; the selection is cut out of it.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
        guard let selection else { return }
        selection.fill(using: .clear)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}
