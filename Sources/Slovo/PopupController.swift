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
        /// Vertical center pinned; the popup grows both ways.
        case middle(CGFloat)
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
    /// Created on first show. `close()` must not create it: a panel built and laid out before it
    /// has a real frame got its glass content stuck off-center.
    private var loadedPanel: PopupPanel?
    private var panel: PopupPanel {
        if let loadedPanel { return loadedPanel }
        let panel = makePanel()
        loadedPanel = panel
        return panel
    }
    private var context = SelectionContext(app: nil, isEditable: true, selectionRect: nil)
    private var whitespace = (leading: "", trailing: "")
    private var anchor = Anchor.top(0)
    private var originX: CGFloat = 0
    private var height = estimatedHeight
    /// Set for a long text: the large card keeps this size, whatever its content.
    private var fixedSize: CGSize?
    private var mouseMonitor: Any?
    private var closeTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var generation = 0
    /// Set while the user drags the popup by its header, until the next programmatic frame change.
    private var isUserMoving = false

    override init() {
        super.init()
        model.onCopy = { [weak self] in self?.copy() }
        model.onReplace = { [weak self] in self?.replace() }
        model.onClose = { [weak self] in self?.close() }
        model.onHeightChange = { [weak self] height in self?.resize(to: height) }
        model.onPhaseChange = { [weak self] phase in self?.phaseChanged(phase) }
        model.onWindowDrag = { [weak self] in self?.userStartedMoving() }
    }

    /// Orders the panel in fully transparent and reveals it once the translation is ready,
    /// or after `skeletonDelay` if it isn't — so the first visible frame already has its final size.
    func show(text: String, context: SelectionContext) {
        prepareForNewPopup()
        self.context = context
        whitespace = (
            String(text.prefix(while: \.isWhitespace)),
            String(text.reversed().prefix(while: \.isWhitespace).reversed())
        )
        model.start(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isEditable: context.isEditable,
            source: context.source
        )
        present(for: context)
    }

    /// An empty popup to write in, under the caret of the field the translation will go into.
    func compose(context: SelectionContext) {
        prepareForNewPopup()
        self.context = context
        whitespace = ("", "")
        model.startComposing(isEditable: context.isEditable)
        present(for: context)
    }

    /// A message-only popup, e.g. "no text found" after a screen capture.
    func showFailure(_ message: String) {
        prepareForNewPopup()
        context = SelectionContext(app: nil, isEditable: false, selectionRect: nil, source: .screen)
        whitespace = ("", "")
        model.showFailure(message)
        present(for: context)
    }

    private func prepareForNewPopup() {
        closeTask?.cancel()
        revealTask?.cancel()
        Speaker.shared.stop()
        generation += 1
        if panel.isVisible { panel.orderOut(nil) }
        // Stays false while the panel is on screen but transparent, laying out its first content.
        model.isRevealed = false
    }

    private func present(for context: SelectionContext) {
        fixedSize = nil
        if model.isPinned {
            positionWherePinned()
        } else if model.isLong {
            positionLongTextCard()
        } else {
            switch context.source {
            case .selection: position(near: context.selectionRect)
            case .screen: positionInMiddleOfScreen()
            }
        }
        setPanelAlpha(0)
        panel.orderFrontRegardless()
        startMouseMonitor()
        scheduleReveal(after: model.phase == .loading ? Self.skeletonDelay : Self.layoutSettleDelay)
    }

    func close(animated: Bool = true) {
        model.isPinned = false
        closeTask?.cancel()
        revealTask?.cancel()
        model.cancel()
        Speaker.shared.stop()
        stopMouseMonitor()
        guard let panel = loadedPanel, panel.isVisible else { return }

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
                self.setPanelAlpha(1)
            }
        }
    }

    /// ⇧⌘2: the popup mustn't end up in the picture. A pinned one only steps aside and keeps its content.
    func hideForScreenCapture() {
        guard model.isPinned else {
            close(animated: false)
            return
        }
        panel.orderOut(nil)
    }

    /// The screen capture was cancelled: a pinned popup comes back as it was.
    func showAgainIfPinned() {
        guard model.isPinned, model.isRevealed, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    // MARK: Actions

    private func copy() {
        guard !model.translation.isEmpty else { return }
        Pasteboard.setString(model.translation)
        model.animated { model.justCopied = true }
        let isPinned = model.isPinned
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(isPinned ? 1200 : 700))
            guard !Task.isCancelled, let self else { return }
            if isPinned {
                self.model.animated { self.model.justCopied = false }
            } else {
                self.close()
            }
        }
    }

    private func replace() {
        guard context.isEditable, !model.translation.isEmpty else { return }
        let text = whitespace.leading + model.translation + whitespace.trailing
        let app = context.app
        guard model.isPinned else {
            // Hide immediately so keyboard focus is back in the source app before ⌘V is posted.
            close(animated: false)
            Task { await TextReplacer.replaceSelection(with: text, in: app) }
            return
        }
        // Pinned: step aside while ⌘V goes to the source app, then come back without taking the
        // keyboard from it. A writing popup comes back empty, ready for the next message.
        panel.orderOut(nil)
        let pastingGeneration = generation
        Task {
            await TextReplacer.replaceSelection(with: text, in: app)
            guard generation == pastingGeneration, model.isPinned else { return }
            model.clearDraft()
            panel.orderFrontRegardless()
        }
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

    /// Text from the screen has no selection to sit next to, and the pointer is wherever the drag
    /// ended, so the popup opens mid-screen, a little above center, like the Settings window.
    private func positionInMiddleOfScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        anchor = .middle(visible.minY + visible.height * 0.55)
        originX = visible.midX - PopupMetrics.width / 2
        applyFrame()
    }

    /// A long text gets a large card in the middle of the screen, sized for reading; the text scrolls inside.
    private func positionLongTextCard() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = Self.longCardSize(in: visible)
        fixedSize = size
        anchor = .middle(visible.midY)
        originX = (visible.midX - size.width / 2).rounded()
        applyFrame()
    }

    private static func longCardSize(in visible: CGRect) -> CGSize {
        CGSize(
            width: min(PopupMetrics.longWidth, visible.width - 80),
            height: (visible.height * PopupMetrics.longHeightFraction).rounded()
        )
    }

    /// A pinned popup keeps its top-left corner; the new content grows down from there, kept on screen.
    private func positionWherePinned() {
        let margin = PopupMetrics.shadowMargin
        let card = panel.frame.insetBy(dx: margin, dy: margin)
        let screen = NSScreen.screens.first { $0.frame.intersects(card) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if model.isLong { fixedSize = Self.longCardSize(in: visible) }
        let width = fixedSize?.width ?? PopupMetrics.width
        anchor = .top(min(card.maxY, visible.maxY - Self.gap))
        originX = min(max(card.minX, visible.minX + Self.gap), visible.maxX - width - Self.gap)
        applyFrame()
    }

    private func resize(to newHeight: CGFloat) {
        guard fixedSize == nil else { return }
        let rounded = ceil(newHeight)
        guard rounded > 0, rounded != height else { return }
        height = rounded
        // Before the reveal nobody sees the panel, so snap; afterwards grow or shrink smoothly.
        applyFrame(animated: model.isRevealed)
    }

    private func targetFrame() -> NSRect {
        let size = fixedSize ?? CGSize(width: PopupMetrics.width, height: height)
        let y: CGFloat
        switch anchor {
        case .top(let top): y = top - size.height
        case .bottom(let bottom): y = bottom
        case .middle(let middle): y = middle - size.height / 2
        }
        let card = NSRect(origin: CGPoint(x: originX, y: y), size: size)
        let margin = PopupMetrics.shadowMargin
        return card.insetBy(dx: -margin, dy: -margin)
    }

    private func applyFrame(animated: Bool = false) {
        let frame = targetFrame()
        setPanelFrame(frame, duration: animated ? 0.22 : 0, timing: .easeInEaseOut)
    }

    /// Every frame change goes through the animator, the instant ones with zero duration. A plain
    /// `setFrame` doesn't stop a reveal or resize animation still running from the previous popup,
    /// which then dragged the window back to its own frame.
    private func setPanelFrame(_ frame: NSRect, duration: TimeInterval = 0, timing: CAMediaTimingFunctionName = .easeOut) {
        isUserMoving = false
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.syncContentSize() }
        }
        guard duration == 0 else { return }
        panel.setFrame(frame, display: true)
        syncContentSize()
    }

    private func setPanelAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0
            panel.animator().alphaValue = alpha
        }
        panel.alphaValue = alpha
    }

    /// The content view follows the window by the size difference, so once an interrupted animation
    /// put them out of step, every later popup kept the error: a short card with only the text field.
    private func syncContentSize() {
        let size = panel.contentRect(forFrameRect: panel.frame).size
        guard let content = panel.contentView, content.frame.size != size else { return }
        content.frame = NSRect(origin: .zero, size: size)
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
        // Flush pending SwiftUI updates and draw while still transparent, so the first visible
        // frame is the new content, not a stale one left from the previous popup.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        model.isRevealed = true

        // Slide in from the selection: down when the popup sits below it, up when above.
        let frame = targetFrame()
        let slide: CGFloat
        switch anchor {
        // A pinned popup appears in place.
        case _ where model.isPinned: slide = 0
        case .top, .middle: slide = Self.revealSlide
        case .bottom: slide = -Self.revealSlide
        }
        setPanelFrame(frame.offsetBy(dx: 0, dy: slide))
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.syncContentSize() }
        }
    }

    // MARK: Moving

    /// Dragging the header pins the popup: it was put somewhere on purpose.
    private func userStartedMoving() {
        isUserMoving = true
        if !model.isPinned { model.animated { model.isPinned = true } }
    }

    func windowDidMove(_ notification: Notification) {
        guard isUserMoving else { return }
        // Later resizes and new content keep the place the popup was dragged to.
        let card = panel.frame.insetBy(dx: PopupMetrics.shadowMargin, dy: PopupMetrics.shadowMargin)
        anchor = .top(card.maxY)
        originX = card.minX
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
        guard !model.isPinned, model.phase != .downloading else { return }
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
        // Start from a real size so the first layout pass never sees an empty frame.
        panel.setFrame(NSRect(origin: .zero, size: targetFrame().size), display: false)
        return panel
    }
}

/// Lays the glass card out inside the shadow margin, clips it to the card shape
/// and draws a shadow around it that matches the corner radius.
private final class PopupContainerView: NSView {
    private let shadowView = ShadowView()
    private let card = NSView()
    private let content: NSView

    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true

        addSubview(shadowView)

        card.wantsLayer = true
        card.layer?.cornerRadius = PopupMetrics.cornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        addSubview(card)
        card.addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Frames are set here rather than by autoresizing: resizing from a degenerate frame (an empty
    /// rect inset by the margin is a null rect) left the content permanently offset in the card.
    override func layout() {
        super.layout()
        layoutCard()
    }

    /// Runs as soon as the window changes size. A layout pass alone doesn't always come before the
    /// panel is revealed, and the new content then sat in a card of the previous popup's size.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutCard()
    }

    private func layoutCard() {
        let margin = PopupMetrics.shadowMargin
        guard bounds.width > margin * 2, bounds.height > margin * 2 else { return }
        shadowView.frame = bounds
        card.frame = bounds.insetBy(dx: margin, dy: margin)
        content.frame = card.bounds
        if let glass = content as? NSGlassEffectView, let inner = glass.contentView {
            inner.frame = glass.bounds
        }
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
        updateShadow()
    }

    /// The shadow follows the card right away, for the same reason as the card itself.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateShadow()
    }

    private func updateShadow() {
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

