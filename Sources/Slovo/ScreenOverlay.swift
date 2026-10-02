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

/// Screenshot of an area and the paragraphs in it.
enum ScreenScanner {
    /// `area` is in AppKit screen coordinates; ScreenCaptureKit wants display space (top-left origin).
    static func capture(_ area: CGRect) async -> CGImage? {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let displayRect = CGRect(x: area.minX, y: primaryHeight - area.maxY, width: area.width, height: area.height)
        return try? await SCScreenshotManager.captureImage(in: displayRect)
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
        let id: Int
        let source: ScreenBlock
        /// Already in the target language, or no words at all: left as it is on the screen.
        var isKept = false
        var translation: String?
    }

    private(set) var blocks: [Block] = []
    private(set) var pair: LanguagePair?
    private(set) var isTranslating = false
    var showsOriginal = false
    var justCopied = false
    /// Where the area and the toolbar sit in the panel, top-left origin.
    private(set) var areaFrame = CGRect.zero
    private(set) var toolbarOrigin = CGPoint.zero
    /// Bumped for every capture, so views start fresh.
    private(set) var session = 0

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}

    func start(blocks: [ScreenBlock], pair: LanguagePair, areaFrame: CGRect, toolbarOrigin: CGPoint) {
        session += 1
        self.pair = pair
        self.areaFrame = areaFrame
        self.toolbarOrigin = toolbarOrigin
        showsOriginal = false
        justCopied = false
        isTranslating = true
        let catalog = LanguageCatalog.shared
        self.blocks = blocks.enumerated().map { index, block in
            let detected = LanguageDetector.detect(block.text, candidates: catalog.keys, preferred: [pair.source, pair.target])
            let isKept = !block.text.contains(where: \.isLetter) || detected == pair.target
            return Block(id: index, source: block, isKept: isKept)
        }
    }

    func setTranslation(_ text: String, ofBlock id: Int) {
        guard blocks.indices.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.2)) { blocks[id].translation = text }
    }

    func finishTranslating() {
        withAnimation { isTranslating = false }
    }

    /// The whole translation in reading order; kept paragraphs as they are.
    var fullTranslation: String {
        blocks.map { $0.translation ?? $0.source.text }.joined(separator: "\n\n")
    }
}

/// Translates the paragraphs in a screen area and draws each translation over its original,
/// in the original's colors, with a small toolbar next to the area.
final class ScreenOverlayController: NSObject, NSWindowDelegate {
    private static let toolbarHeight: CGFloat = 40
    private static let toolbarWidth: CGFloat = 320
    private static let gap: CGFloat = 8

    private let model = ScreenOverlayModel()
    private var loadedPanel: PopupPanel?
    private var task: Task<Void, Never>?
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
    }

    var isShown: Bool { loadedPanel?.isVisible == true }

    /// `area` in AppKit screen coordinates.
    func show(area: CGRect) async {
        close(notify: false)
        // Let the region picker leave the screen before the screenshot.
        try? await Task.sleep(for: .milliseconds(80))
        guard let image = await ScreenScanner.capture(area) else {
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

        let layout = Self.layout(for: area)
        model.start(blocks: blocks, pair: pair, areaFrame: layout.area, toolbarOrigin: layout.toolbar)
        present(frame: layout.panel)
        settings.remember(pair)

        let session = TranslationSession(installedSource: sourceVariant, target: targetVariant)
        task = Task { await translate(with: session) }
    }

    func close() {
        close(notify: true)
    }

    private func close(notify: Bool) {
        task?.cancel()
        task = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        guard let panel = loadedPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        if notify { onClosed() }
    }

    private func copy() {
        Pasteboard.setString(model.fullTranslation)
        withAnimation(.smooth(duration: 0.2)) { model.justCopied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            close()
        }
    }

    private func translate(with session: TranslationSession) async {
        // The SDK isn't Sendable-annotated; the session is only used from here and to cancel it.
        nonisolated(unsafe) let session = session
        let requests = model.blocks.filter { !$0.isKept }.map {
            TranslationSession.Request(sourceText: $0.source.text, clientIdentifier: String($0.id))
        }
        await withTaskCancellationHandler {
            do {
                for try await response in session.translate(batch: requests) {
                    guard !Task.isCancelled else { return }
                    if let id = response.clientIdentifier.flatMap(Int.init) {
                        model.setTranslation(response.targetText, ofBlock: id)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
            }
            // A batch stops at the first paragraph it can't translate; the rest go one by one.
            for block in model.blocks where !block.isKept && block.translation == nil {
                guard let text = (try? await session.translate(block.source.text))?.targetText else { continue }
                guard !Task.isCancelled else { return }
                model.setTranslation(text, ofBlock: block.id)
            }
        } onCancel: {
            session.cancel()
        }
        guard !Task.isCancelled else { return }
        model.finishTranslating()
    }

    /// The panel covers the area plus the toolbar: below the area when there's room, above it
    /// otherwise, or inside its bottom edge on a full-screen area.
    private static func layout(for area: CGRect) -> (panel: CGRect, area: CGRect, toolbar: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? area
        let toolbarX = min(max(area.minX, visible.minX + gap), visible.maxX - toolbarWidth - gap)
        var toolbar = CGRect(x: toolbarX, y: area.minY - gap - toolbarHeight, width: toolbarWidth, height: toolbarHeight)
        if toolbar.minY < visible.minY {
            toolbar.origin.y = area.maxY + gap
            if toolbar.maxY > visible.maxY { toolbar.origin.y = area.minY + gap }
        }
        let panel = area.union(toolbar)
        // Top-left coordinates inside the panel.
        let local = { (rect: CGRect) in
            CGRect(x: rect.minX - panel.minX, y: panel.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return (panel, local(area), local(toolbar).origin)
    }

    private func present(frame: CGRect) {
        let panel = loadedPanel ?? makePanel()
        loadedPanel = panel
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)

        // The picture is a still of what was on screen: any click elsewhere, scrolling or switching
        // apps would leave it over content that has moved, so those close it.
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

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: ScreenOverlayView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}

struct ScreenOverlayView: View {
    @Bindable var model: ScreenOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(model.blocks) { block in
                    if let translation = block.translation, !block.isKept {
                        BlockPatch(block: block.source, text: translation)
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: model.areaFrame.width, height: model.areaFrame.height, alignment: .topLeading)
            .offset(x: model.areaFrame.minX, y: model.areaFrame.minY)
            .opacity(model.showsOriginal ? 0 : 1)

            toolbar
                .offset(x: model.toolbarOrigin.x, y: model.toolbarOrigin.y)
        }
        .id(model.session)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
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
        .focusEffectDisabled()
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
