import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI
import Translation
import Vision

/// A paragraph found in a screen area: its text, where it is, and the colors it's drawn in.
nonisolated struct ScreenBlock: Sendable {
    enum Alignment: Sendable {
        case leading, center, trailing
    }

    let text: String
    /// In points from the area's top-left corner.
    let rect: CGRect
    let lineCount: Int
    let alignment: Alignment
    let background: RGBColor
    let foreground: RGBColor
}

nonisolated struct RGBColor: Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let white = RGBColor(red: 1, green: 1, blue: 1)

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    var color: Color { Color(red: red, green: green, blue: blue) }

    func distance(to other: RGBColor) -> Double {
        let dr = red - other.red, dg = green - other.green, db = blue - other.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

/// A screen area to capture again and again, without Slovo's own windows in the picture: the
/// overlay sits right on top of the area and would otherwise read its own translation back.
final class ScreenAreaCapture {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration) {
        self.filter = filter
        self.configuration = configuration
    }

    /// `area` is in AppKit screen coordinates. An area across two displays is cut to the one with its center.
    static func make(for area: CGRect) async -> ScreenAreaCapture? {
        guard let content = try? await SCShareableContent.current else { return nil }
        // ScreenCaptureKit works in display space: points, top-left origin at the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let displayRect = CGRect(x: area.minX, y: primaryHeight - area.maxY, width: area.width, height: area.height)
        let center = CGPoint(x: displayRect.midX, y: displayRect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
            return nil
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = displayRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int((area.width * scale).rounded())
        configuration.height = Int((area.height * scale).rounded())
        configuration.showsCursor = false
        return ScreenAreaCapture(filter: filter, configuration: configuration)
    }

    func image() async -> CGImage? {
        try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// The paragraphs in a screenshot.
enum ScreenScanner {
    /// Cheap check whether the area changed since the last look, so an unchanged picture isn't read again.
    nonisolated static func fingerprint(of image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let length = CFDataGetLength(data)
        var hasher = Hasher()
        hasher.combine(length)
        for index in stride(from: 0, to: length, by: max(length / 65_536, 1)) {
            hasher.combine(bytes[index])
        }
        return hasher.finalize()
    }

    /// Paragraphs as the document recognizer rebuilds them from wrapped lines, each with the
    /// background and text colors sampled around and inside it.
    nonisolated static func blocks(in image: CGImage, pointSize: CGSize) async -> [ScreenBlock] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        guard let document = try? await request.perform(on: image).first?.document else { return [] }
        let pixels = PixelBuffer(image)
        let pixelSize = CGSize(width: image.width, height: image.height)
        return document.paragraphs.compactMap { paragraph in
            let text = paragraph.transcript
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let box = paragraph.boundingRegion.boundingBox
            let colors = pixels?.colors(around: box.toImageCoordinates(pixelSize, origin: .upperLeft))
            let alignment: ScreenBlock.Alignment = switch paragraph.textAlignment {
            case .center: .center
            case .trailing: .trailing
            default: .leading
            }
            return ScreenBlock(
                text: text,
                rect: box.toImageCoordinates(pointSize, origin: .upperLeft),
                lineCount: max(paragraph.lines.count, 1),
                alignment: alignment,
                background: colors?.background ?? .white,
                foreground: colors?.foreground ?? .black
            )
        }
    }
}

/// RGBA pixels of a screenshot, row 0 at the top, for sampling colors.
private nonisolated struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    private func pixel(_ x: Int, _ y: Int) -> RGBColor {
        let index = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return RGBColor(red: Double(bytes[index]) / 255, green: Double(bytes[index + 1]) / 255, blue: Double(bytes[index + 2]) / 255)
    }

    /// The background is the median color of a ring just outside the text; the text color is what
    /// inside differs from it the most, ignoring the faintest anti-aliased edges.
    func colors(around rect: CGRect) -> (background: RGBColor, foreground: RGBColor) {
        let ring = rect.insetBy(dx: -3, dy: -3).integral
        var border: [RGBColor] = []
        let stepX = max(Int(ring.width) / 60, 1), stepY = max(Int(ring.height) / 20, 1)
        for x in stride(from: Int(ring.minX), through: Int(ring.maxX), by: stepX) {
            border.append(pixel(x, Int(ring.minY)))
            border.append(pixel(x, Int(ring.maxY)))
        }
        for y in stride(from: Int(ring.minY), through: Int(ring.maxY), by: stepY) {
            border.append(pixel(Int(ring.minX), y))
            border.append(pixel(Int(ring.maxX), y))
        }
        let background = Self.median(border)

        var inside: [(distance: Double, color: RGBColor)] = []
        let insideStepX = max(Int(rect.width) / 80, 1), insideStepY = max(Int(rect.height) / 24, 1)
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: insideStepY) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: insideStepX) {
                let color = pixel(x, y)
                inside.append((color.distance(to: background), color))
            }
        }
        inside.sort { $0.distance > $1.distance }
        let strongest = inside.prefix(max(inside.count / 12, 1)).map(\.color)
        var foreground = Self.median(strongest)
        // Too close to the background to read: plain black or white instead.
        if foreground.distance(to: background) < 0.3 {
            foreground = background.luminance > 0.5 ? .black : .white
        }
        return (background, foreground)
    }

    private static func median(_ colors: [RGBColor]) -> RGBColor {
        guard !colors.isEmpty else { return .white }
        func middle(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return RGBColor(red: middle(colors.map(\.red)), green: middle(colors.map(\.green)), blue: middle(colors.map(\.blue)))
    }
}


@Observable
final class ScreenOverlayModel {
    struct Block: Identifiable {
        /// The text plus its occurrence, so a paragraph that stays put keeps its patch between looks.
        let id: String
        let source: ScreenBlock
        /// Already in the target language, or no words at all: left as it is on the screen.
        let isKept: Bool
        var translation: String?
    }

    private(set) var blocks: [Block] = []
    private(set) var pair: LanguagePair?
    /// The first translation of the area; later looks of a pinned overlay update quietly.
    private(set) var isTranslating = false
    /// Pinned: the overlay stays and follows the area as it changes, like live subtitles.
    var isPinned = false
    var showsOriginal = false
    var justCopied = false
    /// Bumped for every new area, so views start fresh.
    private(set) var session = 0

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onPinChange: () -> Void = {}

    func start(pair: LanguagePair) {
        session += 1
        self.pair = pair
        blocks = []
        isPinned = false
        showsOriginal = false
        justCopied = false
        isTranslating = true
    }

    /// The paragraphs of a new look at the area. Ones translated before get their translation
    /// right away; the rest wait for theirs, with the original showing through meanwhile.
    func update(with found: [ScreenBlock], cachedTranslation: (String) -> String?) {
        guard let pair else { return }
        let catalog = LanguageCatalog.shared
        var occurrences: [String: Int] = [:]
        let updated = found.map { block in
            let occurrence = occurrences[block.text, default: 0]
            occurrences[block.text] = occurrence + 1
            let detected = LanguageDetector.detect(block.text, candidates: catalog.keys, preferred: [pair.source, pair.target])
            let isKept = !block.text.contains(where: \.isLetter) || detected == pair.target
            return Block(
                id: "\(occurrence)#\(block.text)", source: block, isKept: isKept,
                translation: isKept ? nil : cachedTranslation(block.text)
            )
        }
        withAnimation(.easeOut(duration: 0.2)) { blocks = updated }
    }

    func setTranslation(_ text: String, ofBlock id: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.2)) { blocks[index].translation = text }
    }

    func finishTranslating() {
        guard isTranslating else { return }
        withAnimation { isTranslating = false }
    }

    var pending: [Block] {
        blocks.filter { !$0.isKept && $0.translation == nil }
    }

    /// The whole translation in reading order; kept paragraphs as they are.
    var fullTranslation: String {
        blocks.map { $0.translation ?? $0.source.text }.joined(separator: "\n\n")
    }
}

/// Translates the paragraphs in a screen area and draws each translation over its original, in the
/// original's colors. The patches live in a window that lets clicks through to the app underneath;
/// the toolbar next to the area is a window of its own.
final class ScreenOverlayController: NSObject {
    private static let toolbarHeight: CGFloat = 40
    private static let toolbarWidth: CGFloat = 360
    private static let gap: CGFloat = 8
    private static let cacheLimit = 500

    private let model = ScreenOverlayModel()
    private var patchesPanel: PopupPanel?
    private var toolbarPanel: PopupPanel?
    private var capture: ScreenAreaCapture?
    /// The SDK isn't Sendable-annotated; the session is only used from the main actor and to cancel it.
    nonisolated(unsafe) private var session: TranslationSession?
    private var task: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    /// Translations made for this area, so text that comes back (a repeated subtitle) isn't translated again.
    private var cache: [String: String] = [:]
    private var lastFingerprint: Int?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    /// No text in the area.
    var onNoText: () -> Void = {}
    /// Languages that need downloading or can't be detected: the regular popup handles those.
    var onNeedsPopup: (String) -> Void = { _ in }
    var onClosed: () -> Void = {}

    override init() {
        super.init()
        model.onClose = { [weak self] in self?.close() }
        model.onCopy = { [weak self] in self?.copy() }
        model.onPinChange = { [weak self] in self?.pinChanged() }
    }

    /// `area` in AppKit screen coordinates.
    func show(area: CGRect) async {
        close(notify: false)
        guard let capture = await ScreenAreaCapture.make(for: area), let image = await capture.image() else {
            onNoText()
            return
        }
        let blocks = await ScreenScanner.blocks(in: image, pointSize: area.size)
        guard !blocks.isEmpty else {
            onNoText()
            return
        }

        let catalog = LanguageCatalog.shared
        await catalog.load()
        let settings = LanguageSettings.shared
        let allText = blocks.map(\.text).joined(separator: "\n\n")
        guard let source = LanguageDetector.detect(allText, candidates: catalog.keys, preferred: [settings.primary, settings.lastForeign]) else {
            onNeedsPopup(allText)
            return
        }
        let pair = LanguagePair(source: source, target: settings.target(forSource: source))
        let sourceVariant = catalog.variant(for: pair.source)
        let targetVariant = catalog.variant(for: pair.target)
        guard await LanguageAvailability().status(from: sourceVariant, to: targetVariant) == .installed else {
            onNeedsPopup(allText)
            return
        }

        self.capture = capture
        session = TranslationSession(installedSource: sourceVariant, target: targetVariant)
        cache = [:]
        lastFingerprint = ScreenScanner.fingerprint(of: image)
        model.start(pair: pair)
        model.update(with: blocks) { _ in nil }
        present(area: area)
        settings.remember(pair)

        task = Task {
            await translatePending()
            model.finishTranslating()
        }
    }

    func close() {
        close(notify: true)
    }

    private func close(notify: Bool) {
        task?.cancel()
        task = nil
        liveTask?.cancel()
        liveTask = nil
        session?.cancel()
        session = nil
        capture = nil
        stopDismissalMonitors()
        let wasShown = toolbarPanel?.isVisible == true
        patchesPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        if notify && wasShown { onClosed() }
    }

    private func copy() {
        Pasteboard.setString(model.fullTranslation)
        withAnimation(.smooth(duration: 0.2)) { model.justCopied = true }
        let isPinned = model.isPinned
        Task {
            try? await Task.sleep(for: .milliseconds(isPinned ? 1200 : 700))
            if isPinned {
                withAnimation(.smooth(duration: 0.2)) { model.justCopied = false }
            } else {
                close()
            }
        }
    }

    // MARK: Translation

    /// Translates the paragraphs that have no translation yet in one batch, each shown as it arrives.
    private func translatePending() async {
        guard let session else { return }
        nonisolated(unsafe) let translator = session
        let pending = model.pending
        guard !pending.isEmpty else { return }
        let requests = pending.map { TranslationSession.Request(sourceText: $0.source.text, clientIdentifier: $0.id) }
        do {
            for try await response in translator.translate(batch: requests) {
                guard !Task.isCancelled else { return }
                if let id = response.clientIdentifier { deliver(response.targetText, for: response.sourceText, blockID: id) }
            }
        } catch {
            guard !Task.isCancelled else { return }
        }
        // A batch stops at the first paragraph it can't translate; the rest go one by one.
        for block in model.pending {
            guard let text = (try? await translator.translate(block.source.text))?.targetText else { continue }
            guard !Task.isCancelled else { return }
            deliver(text, for: block.source.text, blockID: block.id)
        }
    }

    private func deliver(_ translation: String, for source: String, blockID: String) {
        if cache.count >= Self.cacheLimit { cache = [:] }
        cache[source] = translation
        model.setTranslation(translation, ofBlock: blockID)
    }

    // MARK: Live updates

    private func pinChanged() {
        if model.isPinned {
            stopDismissalMonitors()
            startLiveUpdates()
        } else {
            liveTask?.cancel()
            liveTask = nil
            startDismissalMonitors()
        }
    }

    /// How often a pinned overlay looks at the area again: a strip of subtitles is read in a blink
    /// and changes often, a whole window takes longer to read and changes less. Looks at an unchanged
    /// picture stop at the fingerprint, so a short pause costs little.
    private static func liveInterval(for size: CGSize) -> Duration {
        let seconds = min(max(0.15 + size.width * size.height / 1_600_000, 0.15), 1)
        return .milliseconds(Int(seconds * 1000))
    }

    /// Looks at the area again and again; when the picture changed, reads it and translates what's new.
    private func startLiveUpdates() {
        liveTask?.cancel()
        let interval = Self.liveInterval(for: patchesPanel?.frame.size ?? .zero)
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, let capture = self.capture,
                      let image = await capture.image() else { continue }
                let fingerprint = ScreenScanner.fingerprint(of: image)
                guard fingerprint != self.lastFingerprint else { continue }
                self.lastFingerprint = fingerprint
                let size = self.patchesPanel?.frame.size ?? .zero
                let blocks = await ScreenScanner.blocks(in: image, pointSize: size)
                guard !Task.isCancelled else { return }
                self.model.update(with: blocks) { self.cache[$0] }
                await self.translatePending()
            }
        }
    }

    // MARK: Windows

    private func present(area: CGRect) {
        let patches = patchesPanel ?? makePanel(PatchesView(model: model), acceptsClicks: false)
        let toolbar = toolbarPanel ?? makePanel(OverlayToolbar(model: model), acceptsClicks: true)
        patchesPanel = patches
        toolbarPanel = toolbar
        patches.setFrame(area, display: true)
        toolbar.setFrame(Self.toolbarFrame(for: area), display: true)
        patches.orderFrontRegardless()
        toolbar.makeKeyAndOrderFront(nil)
        startDismissalMonitors()
    }

    /// Below the area when there's room, above it otherwise, or inside its bottom edge on a full-screen area.
    private static func toolbarFrame(for area: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? area
        let x = min(max(area.minX, visible.minX + gap), visible.maxX - toolbarWidth - gap)
        var frame = CGRect(x: x, y: area.minY - gap - toolbarHeight, width: toolbarWidth, height: toolbarHeight)
        if frame.minY < visible.minY {
            frame.origin.y = area.maxY + gap
            if frame.maxY > visible.maxY { frame.origin.y = area.minY + gap }
        }
        return frame
    }

    /// Unpinned, the overlay is a still of what was on screen: a click elsewhere, scrolling or
    /// switching apps would leave it over content that has moved, so those close it.
    private func startDismissalMonitors() {
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.close() }) {
            monitors.append(monitor)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopDismissalMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func makePanel(_ view: some View, acceptsClicks: Bool) -> PopupPanel {
        let panel = PopupPanel()
        panel.onCancel = { [weak self] in self?.close() }
        // The patches only show; clicks on them reach the app underneath, e.g. a video's controls.
        panel.ignoresMouseEvents = !acceptsClicks
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}

private struct PatchesView: View {
    let model: ScreenOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.blocks) { block in
                if let translation = block.translation, !block.isKept {
                    BlockPatch(block: block.source, text: translation)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.showsOriginal ? 0 : 1)
        .id(model.session)
    }
}

private struct OverlayToolbar: View {
    @Bindable var model: ScreenOverlayModel

    var body: some View {
        HStack(spacing: 4) {
            if let pair = model.pair {
                let catalog = LanguageCatalog.shared
                HStack(spacing: 6) {
                    Text(catalog.name(for: pair.source)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(catalog.name(for: pair.target))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
            }
            if model.isTranslating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.translating)
            }
            ToolbarIcon(name: model.isPinned ? "pin.fill" : "pin", label: model.isPinned ? L10n.unpinLive : L10n.pinLive) {
                withAnimation(.smooth(duration: 0.2)) { model.isPinned.toggle() }
                model.onPinChange()
            }
            .foregroundStyle(model.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .keyboardShortcut("p", modifiers: .command)
            ToolbarIcon(name: model.showsOriginal ? "eye.slash" : "eye", label: model.showsOriginal ? L10n.showTranslation : L10n.showOriginal) {
                withAnimation(.easeInOut(duration: 0.15)) { model.showsOriginal.toggle() }
            }
            ToolbarIcon(name: model.justCopied ? "checkmark" : "doc.on.doc", label: L10n.copy, action: model.onCopy)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.isTranslating)
            ToolbarIcon(name: "xmark", label: L10n.close, action: model.onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(4)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .id(model.session)
    }
}

private struct ToolbarIcon: View {
    let name: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.borderless)
        // Borderless buttons draw AppKit's focus ring; the shortcuts work without focus anyway.
        .focusable(false)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A translated paragraph over its original: the original's background, its text color, a font
/// sized from its line height, shrunk when the translation is longer.
private struct BlockPatch: View {
    /// Covers the original's anti-aliased edges.
    private static let bleed: CGFloat = 2

    let block: ScreenBlock
    let text: String

    var body: some View {
        let lineHeight = block.rect.height / CGFloat(block.lineCount)
        Text(text)
            .font(.system(size: max(8, lineHeight * 0.78)))
            .foregroundStyle(block.foreground.color)
            .multilineTextAlignment(textAlignment)
            .lineLimit(block.lineCount == 1 ? 1 : block.lineCount + 1)
            .minimumScaleFactor(0.35)
            .frame(
                width: block.rect.width + Self.bleed * 2,
                height: block.rect.height + Self.bleed * 2,
                alignment: frameAlignment
            )
            .background(block.background.color, in: .rect(cornerRadius: 3))
            .offset(x: block.rect.minX - Self.bleed, y: block.rect.minY - Self.bleed)
    }

    private var textAlignment: TextAlignment {
        switch block.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch block.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
