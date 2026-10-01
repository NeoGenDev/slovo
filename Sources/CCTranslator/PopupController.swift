import AppKit
import SwiftUI

/// Borderless floating panel that takes keyboard focus without activating the app,
/// so the source app stays frontmost and keeps its selection for Replace.
final class PopupPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The system shadow traces the standard window shape, drawing a second, less rounded
        // outline around the glass. PopupContainerView draws its own shadow instead.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class PopupController: NSObject, NSWindowDelegate {
    private enum Anchor {
        /// Top edge pinned; the popup grows downward.
        case top(CGFloat)
        /// Bottom edge pinned; the popup grows upward.
        case bottom(CGFloat)
    }

    private static let estimatedHeight: CGFloat = 240
    private static let gap: CGFloat = 8
    /// How long to wait for the translation before showing the skeleton instead.
    private static let skeletonDelay = Duration.milliseconds(300)
    /// One or two display frames for SwiftUI to lay out new content before it's shown.
    private static let layoutSettleDelay = Duration.milliseconds(40)
    /// Distance the popup slides from the selection while fading in.
    private static let revealSlide: CGFloat = 6

    private let model = PopupModel()
    private lazy var panel = makePanel()
    private var context = SelectionContext(app: nil, isEditable: true, selectionRect: nil)
    private var whitespace = (leading: "", trailing: "")
    private var anchor = Anchor.top(0)
    private var originX: CGFloat = 0
    private var height = estimatedHeight
    private var mouseMonitor: Any?
    private var closeTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var generation = 0

    override init() {
        super.init()
        model.onCopy = { [weak self] in self?.copy() }
        model.onReplace = { [weak self] in self?.replace() }
        model.onClose = { [weak self] in self?.close() }
        model.onHeightChange = { [weak self] height in self?.resize(to: height) }
        model.onPhaseChange = { [weak self] phase in self?.phaseChanged(phase) }
    }

    /// Orders the panel in fully transparent and reveals it once the translation is ready,
    /// or after `skeletonDelay` if it isn't — so the first visible frame already has its final size.
    func show(text: String, context: SelectionContext) {
        closeTask?.cancel()
        revealTask?.cancel()
        generation += 1
        if panel.isVisible { panel.orderOut(nil) }
        // Stays false while the panel is on screen but transparent, laying out its first content.
        model.isRevealed = false

        self.context = context
        whitespace = (
            String(text.prefix(while: \.isWhitespace)),
            String(text.reversed().prefix(while: \.isWhitespace).reversed())
        )
        model.start(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isEditable: context.isEditable)

        position(near: context.selectionRect)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        startMouseMonitor()
        scheduleReveal(after: model.phase == .loading ? Self.skeletonDelay : Self.layoutSettleDelay)
    }

    func close(animated: Bool = true) {
        closeTask?.cancel()
        revealTask?.cancel()
        model.cancel()
        stopMouseMonitor()
        guard panel.isVisible else { return }

        guard animated else {
            panel.orderOut(nil)
            return
        }
        let closingGeneration = generation
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new popup may have been shown while this one was fading out.
                guard let self, self.generation == closingGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    // MARK: Actions

    private func copy() {
        guard !model.translation.isEmpty else { return }
        Pasteboard.setString(model.translation)
        model.justCopied = true
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func replace() {
        guard context.isEditable, !model.translation.isEmpty else { return }
        let text = whitespace.leading + model.translation + whitespace.trailing
        let app = context.app
        // Hide immediately so keyboard focus is back in the source app before ⌘V is posted.
        close(animated: false)
        Task { await TextReplacer.replaceSelection(with: text, in: app) }
    }

    // MARK: Layout

    private func position(near selection: CGRect?) {
        let mouse = NSEvent.mouseLocation
        // Without selection bounds, use a small box around the pointer so the popup clears the cursor.
        let reference = selection ?? CGRect(x: mouse.x, y: mouse.y - 12, width: 0, height: 24)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: reference.midX, y: reference.midY)) }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let below = min(reference.minY - Self.gap, visible.maxY - Self.gap)
        if below - Self.estimatedHeight >= visible.minY {
            anchor = .top(below)
        } else {
            anchor = .bottom(min(reference.maxY + Self.gap, visible.maxY - Self.estimatedHeight))
        }

        let pointerOverSelection = selection.map { mouse.x >= $0.minX && mouse.x <= $0.maxX } ?? true
        let preferredX = pointerOverSelection ? mouse.x - 40 : reference.minX
        originX = min(max(preferredX, visible.minX + Self.gap), visible.maxX - PopupMetrics.width - Self.gap)

        applyFrame()
    }

    private func resize(to newHeight: CGFloat) {
        let rounded = ceil(newHeight)
        guard rounded > 0, rounded != height else { return }
        height = rounded
        // Before the reveal nobody sees the panel, so snap; afterwards grow or shrink smoothly.
        applyFrame(animated: model.isRevealed)
    }

    private func targetFrame() -> NSRect {
        let y: CGFloat
        switch anchor {
        case .top(let top): y = top - height
        case .bottom(let bottom): y = bottom
        }
        let card = NSRect(x: originX, y: y, width: PopupMetrics.width, height: height)
        let margin = PopupMetrics.shadowMargin
        return card.insetBy(dx: -margin, dy: -margin)
    }

    private func applyFrame(animated: Bool = false) {
        let frame = targetFrame()
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Reveal

    private func phaseChanged(_ phase: PopupModel.Phase) {
        guard !model.isRevealed, phase != .loading else { return }
        // The result arrived before the skeleton was shown: reveal it as soon as it's laid out.
        scheduleReveal(after: Self.layoutSettleDelay)
    }

    private func scheduleReveal(after delay: Duration) {
        revealTask?.cancel()
        let revealGeneration = generation
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.generation == revealGeneration else { return }
            self.reveal()
        }
    }

    private func reveal() {
        guard !model.isRevealed, panel.isVisible else { return }
        model.isRevealed = true

        // Slide in from the selection: down when the popup sits below it, up when above.
        let frame = targetFrame()
        let slide: CGFloat
        switch anchor {
        case .top: slide = Self.revealSlide
        case .bottom: slide = -Self.revealSlide
        }
        panel.setFrame(frame.offsetBy(dx: 0, dy: slide), display: false)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Dismissal

    func windowDidResignKey(_ notification: Notification) {
        dismissUnlessDownloading()
    }

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        // Global monitors only see clicks in other apps, so clicks inside the popup are unaffected.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismissUnlessDownloading()
        }
    }

    private func stopMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func dismissUnlessDownloading() {
        // The system download prompt takes focus; closing then would cancel the download.
        guard model.phase != .downloading else { return }
        close()
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }

        let hosting = NSHostingView(rootView: PopupView(model: model))
        hosting.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.cornerRadius = PopupMetrics.cornerRadius
        glass.contentView = hosting
        panel.contentView = PopupContainerView(content: glass)
        return panel
    }
}

/// Lays the glass card out inside the shadow margin, clips it to the card shape
/// and draws a shadow around it that matches the corner radius.
private final class PopupContainerView: NSView {
    private let shadowView = ShadowView()
    private let card = NSView()

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true

        shadowView.autoresizingMask = [.width, .height]
        addSubview(shadowView)

        card.wantsLayer = true
        card.layer?.cornerRadius = PopupMetrics.cornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.autoresizingMask = [.width, .height]
        addSubview(card)

        content.frame = card.bounds
        content.autoresizingMask = [.width, .height]
        card.addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        shadowView.frame = bounds
        let margin = PopupMetrics.shadowMargin
        card.frame = bounds.insetBy(dx: margin, dy: margin)
    }
}

private final class ShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        guard let layer else { return }
        let margin = PopupMetrics.shadowMargin
        let radius = PopupMetrics.cornerRadius
        let cardRect = bounds.insetBy(dx: margin, dy: margin)

        layer.shadowPath = CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -8)

        // Cut the shadow out from under the card, otherwise it darkens the translucent glass.
        let hole = cardRect.insetBy(dx: 1, dy: 1)
        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        maskPath.addPath(CGPath(roundedRect: hole, cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
        let mask = CAShapeLayer()
        mask.path = maskPath
        mask.fillRule = .evenOdd
        layer.mask = mask
    }
}
