import AppKit
import SwiftUI
import Translation

enum PopupMetrics {
    static let width: CGFloat = 380
    static let cornerRadius: CGFloat = 26
    static let padding: CGFloat = 14
    static let maxTranslationHeight: CGFloat = 320
    /// Transparent room around the card for its drop shadow.
    static let shadowMargin: CGFloat = 32
}

struct PopupView: View {
    @Bindable var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 8) {
                Text(model.sourceText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // Inset like the translation's text; the speak buttons stay flush right, in one column.
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let pair = model.pair {
                    SpeakButton(text: model.sourceText, language: pair.source, id: "source", label: L10n.speakOriginal)
                }
            }
            content
            if let entry = model.dictionaryEntry, model.phase == .loading || model.phase == .result {
                DictionaryCard(entry: entry)
            }
            footer
        }
        .id(model.session)
        .padding(PopupMetrics.padding)
        .frame(width: PopupMetrics.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .translationTask(model.downloadConfiguration) { session in
            await model.download(using: session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let pair = model.pair {
                LanguageMenu(model: model, pair: pair)
            }
            Spacer(minLength: 0)
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            // Keeps keyboard focus (Space closes the popup) without the blue focus ring.
            .focusEffectDisabled()
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(L10n.close)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            SkeletonLines()
        case .result:
            HStack(alignment: .top, spacing: 8) {
                TranslationText(text: model.translation)
                if let pair = model.pair {
                    SpeakButton(text: model.translation, language: pair.target, id: "translation", label: L10n.speakTranslation)
                        .padding(.top, 3)
                }
            }
            .opacity(model.isRefreshing ? 0.4 : 1)
        case .needsDownload, .downloading:
            downloadPrompt
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var copyTitle: some View {
        HStack(spacing: 6) {
            Text(L10n.copy)
            Text("⌘C").fontWeight(.medium).opacity(0.55)
        }
    }

    private var downloadPrompt: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.languagesNeeded)
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.downloadExplanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(2)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .loading, .result:
            HStack(spacing: 8) {
                if !model.isEditable {
                    Text(L10n.readOnlyField)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: model.onCopy) {
                    HStack(spacing: 6) {
                        ButtonIcon(name: model.justCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        // Hidden copies of both states reserve the wider one's width, so the button
                        // doesn't shrink when "Copy ⌘C" turns into "Copied".
                        ZStack {
                            copyTitle.hidden()
                            Text(L10n.copied).hidden()
                            if model.justCopied {
                                Text(L10n.copied)
                            } else {
                                copyTitle
                            }
                        }
                    }
                }
                .glassButton(prominent: !model.isEditable)
                .keyboardShortcut("c", modifiers: .command)

                if model.isEditable {
                    Button(action: model.onReplace) {
                        HStack(spacing: 6) {
                            ButtonIcon(name: "arrow.left.arrow.right")
                            Text(L10n.replace)
                            Text("↩").fontWeight(.medium).opacity(0.7)
                        }
                    }
                    .glassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .controlSize(.large)
            .disabled(model.phase == .loading || model.isRefreshing)

        case .needsDownload, .downloading:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.notNow, action: model.onClose)
                    .glassButton(prominent: false)
                Button {
                    model.requestDownload()
                } label: {
                    HStack(spacing: 6) {
                        if model.phase == .downloading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: ButtonIcon.size, height: ButtonIcon.size)
                            Text(L10n.downloading)
                        } else {
                            ButtonIcon(name: "arrow.down")
                            Text(L10n.download)
                        }
                    }
                }
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(model.phase == .downloading)
            }
            .font(.system(size: 13, weight: .semibold))
            .controlSize(.large)

        case .failed:
            EmptyView()
        }
    }
}

/// The "English → Russian" pill. Clicking it opens a menu to translate into another language
/// or to correct a wrongly detected source language.
private struct LanguageMenu: View {
    let model: PopupModel
    let pair: LanguagePair

    private let catalog = LanguageCatalog.shared
    private let settings = LanguageSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(catalog.name(for: pair.source))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(catalog.name(for: pair.target))
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .glassEffect(.regular, in: .capsule)
        // SwiftUI's Menu flattens a custom label on macOS and loses the pill's look,
        // so the pill stays a plain view and an AppKit menu opens on click.
        .overlay {
            MenuAnchor(
                accessibilityLabel: "\(catalog.name(for: pair.source)) → \(catalog.name(for: pair.target))",
                makeMenu: makeMenu
            )
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: L10n.translateTo))
        for language in quickTargets {
            menu.addItem(actionMenuItem(title: language.name, isSelected: language.key == pair.target) {
                model.retranslate(target: language.key)
            })
        }
        let others = otherTargets
        if !others.isEmpty {
            menu.addItem(submenu(L10n.otherLanguages, languages: others, selected: pair.target) {
                model.retranslate(target: $0)
            })
        }
        menu.addItem(.separator())
        let sources = catalog.languages.filter { $0.key != pair.target }
        menu.addItem(submenu(L10n.sourceLanguage, languages: sources, selected: pair.source) {
            model.retranslate(source: $0)
        })
        return menu
    }

    private func submenu(
        _ title: String,
        languages: [LanguageCatalog.Language],
        selected: String,
        action: @escaping (String) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for language in languages {
            submenu.addItem(actionMenuItem(title: language.name, isSelected: language.key == selected) {
                action(language.key)
            })
        }
        item.submenu = submenu
        return item
    }

    /// My language and the last one I translated from or into, minus the source.
    private var quickTargets: [LanguageCatalog.Language] {
        [settings.primary, settings.lastForeign]
            .filter { $0 != pair.source }
            .compactMap { key in catalog.languages.first { $0.key == key } }
    }

    private var otherTargets: [LanguageCatalog.Language] {
        let quickKeys = Set(quickTargets.map(\.key))
        return catalog.languages.filter { $0.key != pair.source && !quickKeys.contains($0.key) }
    }
}

/// Transparent click target laid over a SwiftUI view; opens an AppKit menu just below it.
private struct MenuAnchor: NSViewRepresentable {
    let accessibilityLabel: String
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.makeMenu = makeMenu
        view.setAccessibilityLabel(accessibilityLabel)
    }

    final class AnchorView: NSView {
        var makeMenu: (() -> NSMenu)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            setAccessibilityElement(true)
            setAccessibilityRole(.popUpButton)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        override func accessibilityPerformPress() -> Bool {
            showMenu()
            return true
        }

        private func showMenu() {
            guard let menu = makeMenu?() else { return }
            // Non-flipped view: y = 0 is the bottom edge, so this opens the menu just under the pill.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
        }
    }
}

/// Menu item that runs a closure. NSMenuItem holds its target weakly, so the item keeps it alive
/// through `representedObject`.
private func actionMenuItem(title: String, isSelected: Bool, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    item.state = isSelected ? .on : .off
    return item
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}

/// Reads its text aloud; while reading, the icon animates and a second click stops it.
private struct SpeakButton: View {
    let text: String
    /// `LanguageCatalog` key.
    let language: String
    let id: String
    let label: String

    private let speaker = Speaker.shared

    var body: some View {
        let isSpeaking = speaker.speakingID == id
        Button {
            speaker.toggle(text, language: LanguageCatalog.shared.variant(for: language), id: id)
        } label: {
            Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isSpeaking ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help(isSpeaking ? L10n.stopSpeaking : label)
        .accessibilityLabel(isSpeaking ? L10n.stopSpeaking : label)
    }
}

/// Pronunciation and a short dictionary entry for a single word, with a way to the full entry.
private struct DictionaryCard: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pronunciation = entry.pronunciation {
                Text(pronunciation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Button(L10n.openInDictionary, action: entry.openInDictionaryApp)
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Concentric with the popup: its 26 pt corners minus the 14 pt padding.
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: PopupMetrics.cornerRadius - PopupMetrics.padding))
    }
}

/// Selectable translation that grows with its text, then scrolls past `maxTranslationHeight`.
/// Inside the popup's `fixedSize`, a ScrollView takes its content's height, so the size is right on the first pass.
private struct TranslationText: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: PopupMetrics.maxTranslationHeight)
    }
}

private struct SkeletonLines: View {
    @State private var dimmed = false
    private let lineWidth = PopupMetrics.width - PopupMetrics.padding * 2 - 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([1.0, 0.86, 0.52], id: \.self) { fraction in
                Capsule()
                    .fill(.primary.opacity(0.1))
                    .frame(width: lineWidth * fraction, height: 13)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dimmed)
        .onAppear { dimmed = true }
        .accessibilityElement()
        .accessibilityLabel(L10n.translating)
    }
}

/// SF Symbols differ in height (doc.on.doc is taller than checkmark), which made the buttons — and the
/// whole popup — change height when an icon swapped. A fixed box keeps every button the same height.
private struct ButtonIcon: View {
    static let size: CGFloat = 16
    let name: String

    var body: some View {
        Image(systemName: name)
            .frame(width: Self.size, height: Self.size)
    }
}

private extension View {
    @ViewBuilder
    func glassButton(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
