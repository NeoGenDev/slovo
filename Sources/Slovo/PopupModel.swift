import Foundation
import Observation
import SwiftUI
import Translation

/// Source and target as `LanguageCatalog` keys.
struct LanguagePair: Equatable {
    var source: String
    var target: String
}

@Observable
final class PopupModel {
    /// "Improve with AI": the result replaces Apple's translation once it's complete.
    enum Improvement: Equatable {
        case idle
        case working
        case done
        case failed(String)
    }

    /// A piece of a long text, translated on its own.
    struct Chunk: Identifiable {
        let id: Int
        let source: String
        /// The whitespace that followed it in the original.
        let separator: String
        var translation: String?
    }

    /// A language of the pair and whether it's on the Mac, for the download prompt.
    struct LanguageDownload: Identifiable, Equatable {
        let key: String
        var isInstalled: Bool
        var id: String { key }
    }

    /// From this length the popup becomes a large reading card that translates the text piece by piece.
    static let longTextThreshold = 1024

    enum Phase: Equatable {
        case loading
        case result
        case needsDownload
        case downloading
        case failed(String)
    }

    private(set) var phase: Phase = .loading {
        didSet { onPhaseChange(phase) }
    }
    private(set) var sourceText = ""
    private(set) var translation = ""
    private(set) var pair: LanguagePair?
    /// For a single word: its entry from Dictionary.app, shown under the translation.
    private(set) var dictionaryEntry: DictionaryEntry?
    /// Re-translating after a language change: the previous result stays visible, dimmed.
    private(set) var isRefreshing = false
    private(set) var improvement = Improvement.idle
    /// Who rewrote the translation, for the "Improved by …" caption.
    private(set) var improvedBy = ""
    /// A long text: shown in the large card as `chunks`, translated piece by piece.
    private(set) var isLong = false
    private(set) var chunks: [Chunk] = []
    private(set) var translatedChunkCount = 0
    /// Writing mode: the user types in `draft`, and the translation follows as they type.
    private(set) var isComposing = false
    var draft = "" {
        didSet {
            if isComposing, draft != oldValue { scheduleComposedTranslation() }
        }
    }
    private(set) var isEditable = true
    private(set) var textSource = TextSource.selection
    var justCopied = false
    /// A pinned popup stays open when focus moves elsewhere, and the next translations open in it.
    /// Only closing it unpins.
    var isPinned = false
    /// Bumped for every new popup. The view uses it as its identity, so each popup starts from fresh
    /// views instead of transitioning from the previous one's (e.g. the ✓ morphing back into the copy icon).
    private(set) var session = 0
    /// Set by the controller once the panel is visible; content changes before that shouldn't animate.
    var isRevealed = false
    /// The pair's languages while some need downloading, each with its own status.
    private(set) var downloads: [LanguageDownload] = []
    /// macOS's own download window is open: nothing downloads until the user confirms there.
    private(set) var isAwaitingSystemPrompt = false
    /// Non-nil while a language download is requested; drives `.translationTask` in the view.
    private(set) var downloadConfiguration: TranslationSession.Configuration?

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onReplace: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onHeightChange: (CGFloat) -> Void = { _ in }
    @ObservationIgnored var onPhaseChange: (Phase) -> Void = { _ in }
    /// The header is being dragged: the popup moves with the pointer and stays where it's put.
    @ObservationIgnored var onWindowDrag: () -> Void = {}

    @ObservationIgnored private let catalog = LanguageCatalog.shared
    @ObservationIgnored private let settings = LanguageSettings.shared
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var improveTask: Task<Void, Never>?
    /// The text the current `translation` was made from; in writing mode typing can get ahead of it.
    @ObservationIgnored private var translatedSource = ""
    @ObservationIgnored private var isSubmitting = false
    /// A pause in typing before the draft is translated.
    private static let composeDelay = Duration.milliseconds(250)

    func start(text: String, isEditable: Bool, source: TextSource) {
        reset(text: text, isEditable: isEditable, source: source)
        isLong = text.count >= Self.longTextThreshold
        if isLong {
            chunks = TextChunker.pieces(of: text).enumerated().map { index, piece in
                Chunk(id: index, source: piece.text, separator: piece.separator)
            }
        } else {
            dictionaryEntry = DictionaryLookup.entry(for: text)
        }
        phase = .loading

        task = Task {
            await catalog.load()
            guard !Task.isCancelled else { return }
            let preferred = [settings.primary, settings.lastForeign]
            guard let source = LanguageDetector.detect(text, candidates: catalog.keys, preferred: preferred) else {
                fail(L10n.couldNotDetectLanguage)
                return
            }
            let pair = LanguagePair(source: source, target: settings.target(forSource: source))
            self.pair = pair
            await translate(pair)
        }
    }

    /// An empty popup to write in your language; the translation goes into the language of the conversation.
    func startComposing(isEditable: Bool) {
        reset(text: "", isEditable: isEditable, source: .selection)
        isComposing = true
        let source = settings.primary
        pair = LanguagePair(source: source, target: settings.target(forSource: source))
        phase = .result
    }

    /// A popup that only carries a message, e.g. when a screen area had no text in it.
    func showFailure(_ message: String) {
        reset(text: "", isEditable: false, source: .screen)
        phase = .failed(message)
    }

    private func reset(text: String, isEditable: Bool, source: TextSource) {
        cancel()
        sourceText = text
        translation = ""
        pair = nil
        dictionaryEntry = nil
        downloads = []
        isAwaitingSystemPrompt = false
        isComposing = false
        draft = ""
        translatedSource = ""
        isSubmitting = false
        isLong = false
        chunks = []
        translatedChunkCount = 0
        isRefreshing = false
        improvement = .idle
        justCopied = false
        downloadConfiguration = nil
        self.isEditable = isEditable
        textSource = source
        session += 1
    }

    /// Translates the same text again with a language picked in the popup's menu.
    func retranslate(source: String? = nil, target: String? = nil) {
        guard var pair = self.pair else { return }
        if let source { pair.source = source }
        if let target { pair.target = target }
        guard pair != self.pair, pair.source != pair.target else { return }

        cancel()
        if isComposing {
            sourceText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            // Nothing typed yet: only the languages change.
            guard !sourceText.isEmpty else {
                self.pair = pair
                return
            }
        }
        downloadConfiguration = nil
        animated {
            self.pair = pair
            justCopied = false
            improvement = .idle
            if phase == .result {
                isRefreshing = true
            } else {
                phase = .loading
            }
        }
        task = Task { await translate(pair) }
    }

    /// Animates content changes only while the popup is on screen. SwiftUI may apply a change made
    /// while the panel is still transparent only after it appears, so the animation is bound to the
    /// change itself (`withAnimation`), not to the value, and resets never animate.
    func animated(_ changes: () -> Void) {
        withAnimation(isRevealed ? .smooth(duration: 0.2) : nil, changes)
    }

    func cancel() {
        task?.cancel()
        task = nil
        improveTask?.cancel()
        improveTask = nil
    }

    var canImprove: Bool {
        !isLong && phase == .result && !isRefreshing && improvement != .working && improvement != .done
    }

    var isTranslatingChunks: Bool {
        isLong && translatedChunkCount < chunks.count
    }

    /// Sends the text and Apple's draft to the AI provider; Apple's translation stays (dimmed) until the result is in.
    func improve() {
        let settings = AISettings.shared
        guard canImprove, settings.isConfigured, let pair else { return }
        let improver = settings.improverName
        let source = sourceText
        let draft = translation
        animated { improvement = .working }
        improveTask = Task {
            do {
                let improved = try await AITranslator.improve(
                    source: source, draft: draft, from: pair.source, to: pair.target, settings: settings
                )
                guard !Task.isCancelled else { return }
                TranslationHistory.shared.record(source: source, translation: improved, pair: pair)
                animated {
                    translation = improved
                    improvedBy = improver
                    improvement = .done
                }
            } catch {
                guard !Task.isCancelled else { return }
                animated { improvement = .failed(error.localizedDescription) }
            }
        }
    }

    /// Translates the draft once typing pauses. The previous translation stays until the new one is in.
    private func scheduleComposedTranslation() {
        task?.cancel()
        improveTask?.cancel()
        if improvement != .idle { animated { improvement = .idle } }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair, !text.isEmpty else {
            animated {
                translation = ""
                if phase != .needsDownload && phase != .downloading { phase = .result }
            }
            translatedSource = ""
            return
        }
        task = Task {
            try? await Task.sleep(for: Self.composeDelay)
            guard !Task.isCancelled else { return }
            sourceText = text
            await translate(pair)
        }
    }

    var canSubmitComposition: Bool {
        isComposing && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phase == .result && improvement != .working
    }

    /// ↩ or a button in writing mode: inserts (or copies) the translation of exactly what's typed,
    /// translating the last keystrokes first if typing got ahead of the translation.
    func submitComposition(insert: Bool) {
        guard canSubmitComposition, !isSubmitting, let pair else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        if text == translatedSource, !translation.isEmpty {
            finishComposing(pair, insert: insert)
            return
        }
        task?.cancel()
        sourceText = text
        task = Task {
            await translate(pair)
            guard !Task.isCancelled, phase == .result, translatedSource == text else {
                isSubmitting = false
                return
            }
            finishComposing(pair, insert: insert)
        }
    }

    private func finishComposing(_ pair: LanguagePair, insert: Bool) {
        settings.remember(pair)
        TranslationHistory.shared.record(source: translatedSource, translation: translation, pair: pair)
        if insert && isEditable {
            onReplace()
        } else {
            onCopy()
        }
        // A pinned popup stays open for the next message.
        isSubmitting = false
    }

    /// After inserting into a pinned popup: an empty field for the next message.
    func clearDraft() {
        guard isComposing else { return }
        draft = ""
    }

    func requestDownload() {
        guard let pair else { return }
        animated { phase = .downloading }
        downloadConfiguration = TranslationSession.Configuration(
            source: catalog.variant(for: pair.source),
            target: catalog.variant(for: pair.target)
        )
    }

    var missingLanguageCount: Int {
        downloads.filter { !$0.isInstalled }.count
    }

    /// Runs inside `.translationTask` — the only kind of session allowed to ask the system to download languages.
    /// macOS shows its own window, where the user starts each download; apps can't download without it.
    /// Meanwhile the popup checks each language every second, and once both are on the Mac it translates.
    /// The window closes before the download lands ("it continues in the background").
    func download(using session: TranslationSession) async {
        // The SDK isn't Sendable-annotated, but this is exactly how Apple intends the session to be used.
        nonisolated(unsafe) let session = session
        guard let pair else { return }
        let downloadSession = self.session
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDownloads(for: pair)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { watcher.cancel() }

        animated { isAwaitingSystemPrompt = true }
        do {
            try await session.prepareTranslation()
        } catch {
            // Cancelled in the system window: offer the download again.
            downloadConfiguration = nil
            guard self.session == downloadSession else { return }
            await refreshDownloads(for: pair)
            animated {
                isAwaitingSystemPrompt = false
                phase = .needsDownload
            }
            return
        }
        animated { isAwaitingSystemPrompt = false }
        for _ in 0..<180 where missingLanguageCount > 0 {
            try? await Task.sleep(for: .seconds(1))
            await refreshDownloads(for: pair)
        }
        downloadConfiguration = nil
        // A newer popup took over meanwhile.
        guard self.session == downloadSession else { return }
        // The window was closed without downloading, or the download stalled: offer it again.
        guard missingLanguageCount == 0 else {
            animated { phase = .needsDownload }
            return
        }
        // Translated by the model's own task, which closing the popup cancels.
        task = Task { await translate(pair) }
    }

    /// Each language of the pair on its own, so the prompt can say which one is missing.
    private func refreshDownloads(for pair: LanguagePair) async {
        var updated: [LanguageDownload] = []
        for key in [pair.source, pair.target] where !updated.contains(where: { $0.key == key }) {
            let isInstalled = await LanguageCatalog.status(of: catalog.variant(for: key)) == .installed
            updated.append(LanguageDownload(key: key, isInstalled: isInstalled))
        }
        guard updated != downloads else { return }
        animated { downloads = updated }
    }

    private func translate(_ pair: LanguagePair) async {
        let source = catalog.variant(for: pair.source)
        let target = catalog.variant(for: pair.target)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }

        switch status {
        case .installed:
            let session = TranslationSession(installedSource: source, target: target)
            if isLong {
                await translateChunks(with: session, pair: pair)
                return
            }
            do {
                let text = sourceText
                let response = try await session.translate(text)
                guard !Task.isCancelled else { return }
                didTranslate(pair, into: response.targetText)
                translatedSource = text
                animated {
                    translation = response.targetText
                    isRefreshing = false
                    phase = .result
                }
            } catch {
                guard !Task.isCancelled else { return }
                fail(L10n.translationFailed(error.localizedDescription))
            }
        case .supported:
            await refreshDownloads(for: pair)
            guard !Task.isCancelled else { return }
            animated {
                isRefreshing = false
                phase = .needsDownload
            }
        case .unsupported:
            fail(L10n.directionUnsupported)
        @unknown default:
            fail(L10n.translationUnavailable)
        }
    }

    /// All pieces go in one batch; each translation replaces its original as soon as it's ready,
    /// so the beginning can be read while the rest is still translating.
    private func translateChunks(with session: TranslationSession, pair: LanguagePair) async {
        // The SDK isn't Sendable-annotated; the session is only used from here and to cancel it.
        nonisolated(unsafe) let session = session
        animated {
            for index in chunks.indices { chunks[index].translation = nil }
            translatedChunkCount = 0
            translation = ""
            isRefreshing = false
            phase = .result
        }
        let requests = chunks.map { TranslationSession.Request(sourceText: $0.source, clientIdentifier: String($0.id)) }
        await withTaskCancellationHandler {
            do {
                for try await response in session.translate(batch: requests) {
                    guard !Task.isCancelled else { return }
                    if let id = response.clientIdentifier.flatMap(Int.init) {
                        setTranslation(response.targetText, ofChunk: id)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
            }
            // A batch stops at the first piece it can't translate. The rest go one by one,
            // and a piece that fails on its own stays in the original language.
            for chunk in chunks where chunk.translation == nil {
                let text = (try? await session.translate(chunk.source))?.targetText ?? chunk.source
                guard !Task.isCancelled else { return }
                setTranslation(text, ofChunk: chunk.id)
            }
        } onCancel: {
            session.cancel()
        }
        guard !Task.isCancelled else { return }
        translation = chunks.map { ($0.translation ?? $0.source) + $0.separator }.joined()
        // Remembered for the language choice, but not kept in History: the menu is for short texts.
        settings.remember(pair)
    }

    private func setTranslation(_ text: String, ofChunk id: Int) {
        guard chunks.indices.contains(id), chunks[id].translation == nil else { return }
        chunks[id].translation = text
        translatedChunkCount += 1
    }

    private func didTranslate(_ pair: LanguagePair, into translation: String) {
        // While writing, every pause in typing is translated; only what's inserted or copied counts.
        guard !isComposing else { return }
        settings.remember(pair)
        TranslationHistory.shared.record(source: sourceText, translation: translation, pair: pair)
    }

    private func fail(_ message: String) {
        animated {
            isRefreshing = false
            phase = .failed(message)
        }
    }
}
