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
    /// "Improve with Claude": the result replaces Apple's translation once it's complete.
    enum Improvement: Equatable {
        case idle
        case working
        case done
        case failed(String)
    }

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
    private(set) var isEditable = true
    private(set) var textSource = TextSource.selection
    var justCopied = false
    /// Bumped for every new popup. The view uses it as its identity, so each popup starts from fresh
    /// views instead of transitioning from the previous one's (e.g. the ✓ morphing back into the copy icon).
    private(set) var session = 0
    /// Set by the controller once the panel is visible; content changes before that shouldn't animate.
    var isRevealed = false
    /// Non-nil while a language download is requested; drives `.translationTask` in the view.
    private(set) var downloadConfiguration: TranslationSession.Configuration?

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onReplace: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onHeightChange: (CGFloat) -> Void = { _ in }
    @ObservationIgnored var onPhaseChange: (Phase) -> Void = { _ in }

    @ObservationIgnored private let catalog = LanguageCatalog.shared
    @ObservationIgnored private let settings = LanguageSettings.shared
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var improveTask: Task<Void, Never>?

    func start(text: String, isEditable: Bool, source: TextSource) {
        reset(text: text, isEditable: isEditable, source: source)
        dictionaryEntry = DictionaryLookup.entry(for: text)
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
        phase == .result && !isRefreshing && improvement != .working && improvement != .done
    }

    /// Sends the text and Apple's draft to Claude; Apple's translation stays (dimmed) until the result is in.
    func improve() {
        let claude = ClaudeSettings.shared
        guard canImprove, let pair, let apiKey = claude.apiKey else { return }
        let model = claude.model
        let source = sourceText
        let draft = translation
        animated { improvement = .working }
        improveTask = Task {
            do {
                let improved = try await ClaudeTranslator.improve(
                    source: source, draft: draft, from: pair.source, to: pair.target, model: model, apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                TranslationHistory.shared.record(source: source, translation: improved, pair: pair)
                animated {
                    translation = improved
                    improvement = .done
                }
            } catch {
                guard !Task.isCancelled else { return }
                animated { improvement = .failed(error.localizedDescription) }
            }
        }
    }

    func requestDownload() {
        guard let pair else { return }
        animated { phase = .downloading }
        downloadConfiguration = TranslationSession.Configuration(
            source: catalog.variant(for: pair.source),
            target: catalog.variant(for: pair.target)
        )
    }

    /// Runs inside `.translationTask` — the only kind of session allowed to ask the system to download languages.
    func download(using session: TranslationSession) async {
        // The SDK isn't Sendable-annotated, but this is exactly how Apple intends the session to be used.
        nonisolated(unsafe) let session = session
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(sourceText)
            if let pair { didTranslate(pair, into: response.targetText) }
            animated {
                translation = response.targetText
                phase = .result
            }
        } catch {
            fail(L10n.languagesNotDownloaded)
        }
        downloadConfiguration = nil
    }

    private func translate(_ pair: LanguagePair) async {
        let source = catalog.variant(for: pair.source)
        let target = catalog.variant(for: pair.target)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }

        switch status {
        case .installed:
            let session = TranslationSession(installedSource: source, target: target)
            do {
                let response = try await session.translate(sourceText)
                guard !Task.isCancelled else { return }
                didTranslate(pair, into: response.targetText)
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

    private func didTranslate(_ pair: LanguagePair, into translation: String) {
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
