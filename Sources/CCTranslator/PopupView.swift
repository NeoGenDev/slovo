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
            Text(model.source)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 2)
            content
            footer
        }
        .padding(PopupMetrics.padding)
        .frame(width: PopupMetrics.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(model.isRevealed ? .smooth(duration: 0.2) : nil, value: model.phase)
        .animation(.smooth(duration: 0.2), value: model.justCopied)
        .translationTask(model.downloadConfiguration) { session in
            await model.download(using: session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let direction = model.direction {
                HStack(spacing: 6) {
                    Text(direction.sourceName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(direction.targetName)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
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
            TranslationText(text: model.translation)
        case .needsDownload, .downloading:
            downloadPrompt
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                        Image(systemName: model.justCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        Text(model.justCopied ? L10n.copied : L10n.copy)
                        if !model.justCopied {
                            Text("⌘C").fontWeight(.medium).opacity(0.55)
                        }
                    }
                }
                .glassButton(prominent: !model.isEditable)
                .keyboardShortcut("c", modifiers: .command)

                if model.isEditable {
                    Button(action: model.onReplace) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
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
            .disabled(model.phase == .loading)

        case .needsDownload, .downloading:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.notNow, action: model.onClose)
                    .glassButton(prominent: false)
                Button {
                    model.requestDownload()
                } label: {
                    if model.phase == .downloading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.downloading)
                        }
                    } else {
                        Label(L10n.download, systemImage: "arrow.down")
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
