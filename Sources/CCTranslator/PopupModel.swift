import Foundation
import Observation
import Translation

enum Direction: Equatable {
    case englishToRussian
    case russianToEnglish

    /// Counts Cyrillic vs Latin letters; nil when the text has neither.
    static func detect(in text: String) -> Direction? {
        var cyrillic = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: cyrillic += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        guard cyrillic + latin > 0 else { return nil }
        return cyrillic > latin ? .russianToEnglish : .englishToRussian
    }

    var source: Locale.Language { self == .englishToRussian ? Self.english : Self.russian }
    var target: Locale.Language { self == .englishToRussian ? Self.russian : Self.english }
    var sourceName: String { self == .englishToRussian ? L10n.english : L10n.russian }
    var targetName: String { self == .englishToRussian ? L10n.russian : L10n.english }

    private static let english = Locale.Language(identifier: "en")
    private static let russian = Locale.Language(identifier: "ru")
}

@Observable
final class PopupModel {
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
    private(set) var source = ""
    private(set) var translation = ""
    private(set) var direction: Direction?
    private(set) var isEditable = true
    var justCopied = false
    /// Set by the controller once the panel is visible; content changes before that shouldn't animate.
    var isRevealed = false
    /// Non-nil while a language download is requested; drives `.translationTask` in the view.
    private(set) var downloadConfiguration: TranslationSession.Configuration?

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onReplace: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onHeightChange: (CGFloat) -> Void = { _ in }
    @ObservationIgnored var onPhaseChange: (Phase) -> Void = { _ in }

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(text: String, isEditable: Bool) {
        cancel()
        source = text
        translation = ""
        justCopied = false
        downloadConfiguration = nil
        self.isEditable = isEditable
        direction = Direction.detect(in: text)

        guard let direction else {
            phase = .failed(L10n.onlyRussianAndEnglish)
            return
        }
        phase = .loading
        task = Task { await translateWithInstalledLanguages(text, direction) }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func requestDownload() {
        guard let direction else { return }
        phase = .downloading
        downloadConfiguration = TranslationSession.Configuration(source: direction.source, target: direction.target)
    }

    /// Runs inside `.translationTask` — the only kind of session allowed to ask the system to download languages.
    func download(using session: TranslationSession) async {
        // The SDK isn't Sendable-annotated, but this is exactly how Apple intends the session to be used.
        nonisolated(unsafe) let session = session
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(source)
            translation = response.targetText
            phase = .result
        } catch {
            phase = .failed(L10n.languagesNotDownloaded)
        }
        downloadConfiguration = nil
    }

    private func translateWithInstalledLanguages(_ text: String, _ direction: Direction) async {
        let status = await LanguageAvailability().status(from: direction.source, to: direction.target)
        guard !Task.isCancelled else { return }

        switch status {
        case .installed:
            let session = TranslationSession(installedSource: direction.source, target: direction.target)
            do {
                let response = try await session.translate(text)
                guard !Task.isCancelled else { return }
                translation = response.targetText
                phase = .result
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(L10n.translationFailed(error.localizedDescription))
            }
        case .supported:
            phase = .needsDownload
        case .unsupported:
            phase = .failed(L10n.directionUnsupported)
        @unknown default:
            phase = .failed(L10n.translationUnavailable)
        }
    }
}
