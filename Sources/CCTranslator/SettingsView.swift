import SwiftUI
import Translation

struct SettingsView: View {
    @Bindable var settings: LanguageSettings
    @Bindable var controller: AppController
    let catalog: LanguageCatalog

    /// Keys of downloaded languages; nil until the first check finishes.
    @State private var installed: Set<String>?
    @State private var downloading: String?
    @State private var downloadConfiguration: TranslationSession.Configuration?

    var body: some View {
        Form {
            Section {
                if catalog.languages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Picker(L10n.myLanguage, selection: $settings.primary) {
                        ForEach(catalog.languages) { language in
                            Text(language.name).tag(language.key)
                        }
                    }
                }
            } header: {
                Text(L10n.translation)
            } footer: {
                Text(L10n.myLanguageFooter(lastForeign: catalog.name(for: settings.lastForeign)))
                    .foregroundStyle(.secondary)
            }

            Section {
                downloadedLanguages
            } header: {
                Text(L10n.downloadedLanguages)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.downloadedFooter)
                        .foregroundStyle(.secondary)
                    Button(L10n.manageInSystemSettings, action: openTranslationSettings)
                        .buttonStyle(.link)
                }
            }

            Section(L10n.general) {
                LabeledContent(L10n.shortcut, value: "⌘C C")
                Toggle(L10n.openAtLogin, isOn: $controller.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: catalog.languages.count) {
            await refreshInstalled()
        }
        // Languages may have been removed in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshInstalled() }
        }
        .translationTask(downloadConfiguration) { session in
            await finishDownload(using: session)
        }
    }

    @ViewBuilder
    private var downloadedLanguages: some View {
        if let installed {
            let downloaded = catalog.languages.filter { installed.contains($0.key) }
            let available = catalog.languages.filter { !installed.contains($0.key) && $0.key != downloading }

            if downloaded.isEmpty && downloading == nil {
                Text(L10n.nothingDownloaded)
                    .foregroundStyle(.secondary)
            }
            ForEach(downloaded) { language in
                LabeledContent(language.name) {
                    if language.key == settings.primary {
                        Text(L10n.myLanguage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let downloading {
                LabeledContent(catalog.name(for: downloading)) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if !available.isEmpty {
                Menu {
                    ForEach(available) { language in
                        Button(language.name) { startDownload(language.key) }
                    }
                } label: {
                    Label(L10n.downloadLanguage, systemImage: "arrow.down.circle")
                }
                .menuStyle(.button)
                .fixedSize()
                .disabled(downloading != nil)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func refreshInstalled() async {
        guard !catalog.languages.isEmpty else { return }
        var result = Set<String>()
        for language in catalog.languages {
            if await LanguageCatalog.status(of: language.variant) == .installed {
                result.insert(language.key)
            }
        }
        installed = result
    }

    private func startDownload(_ key: String) {
        // Translation downloads pairs; pairing with a language that's already here fetches only the new one.
        let partner = [settings.primary, settings.lastForeign, "en", "ru"]
            .first { $0 != key && installed?.contains($0) == true }
            ?? (key == "en" ? "ru" : "en")
        downloading = key
        downloadConfiguration = TranslationSession.Configuration(
            source: catalog.variant(for: key),
            target: catalog.variant(for: partner)
        )
    }

    private func finishDownload(using session: TranslationSession) async {
        // The SDK isn't Sendable-annotated, but this is exactly how Apple intends the session to be used.
        nonisolated(unsafe) let session = session
        if let key = downloading {
            do {
                try await session.prepareTranslation()
                // The call can return before the download lands; keep the spinner until it does.
                for _ in 0..<120 {
                    if await LanguageCatalog.status(of: catalog.variant(for: key)) == .installed { break }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                // Cancelled in the system prompt, or the window closed.
            }
        }
        downloadConfiguration = nil
        downloading = nil
        await refreshInstalled()
    }

    private func openTranslationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
