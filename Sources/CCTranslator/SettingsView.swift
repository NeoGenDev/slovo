import SwiftUI
import Translation
import UniformTypeIdentifiers

/// Settings window: one tab per area, so the window stays as tall as the open tab needs.
struct SettingsView: View {
    private enum Tab: String {
        case general, languages, exclusions, claude
    }

    @Bindable var settings: LanguageSettings
    @Bindable var controller: AppController
    let catalog: LanguageCatalog

    /// Reopens on the tab that was open last time.
    @AppStorage("settingsTab") private var selectedTab = Tab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab(L10n.general, systemImage: "gearshape", value: Tab.general) {
                GeneralPane(controller: controller)
            }
            SwiftUI.Tab(L10n.languagesTab, systemImage: "globe", value: Tab.languages) {
                LanguagesPane(settings: settings, catalog: catalog)
            }
            SwiftUI.Tab(L10n.excludedApps, systemImage: "hand.raised", value: Tab.exclusions) {
                ExclusionsPane()
            }
            SwiftUI.Tab("Claude", systemImage: "sparkles", value: Tab.claude) {
                ClaudePane()
            }
        }
    }
}

private extension View {
    /// A tab's form: fixed width, as tall as its content.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralPane: View {
    @Bindable var controller: AppController

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.selectedTextShortcut, value: "⌘C C")
                LabeledContent(L10n.screenAreaShortcut, value: "⇧⌘2")
            } header: {
                Text(L10n.shortcut)
            } footer: {
                Text(L10n.screenAreaFooter)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L10n.openAtLogin, isOn: $controller.launchAtLogin)
            }
        }
        .settingsPane()
    }
}

private struct LanguagesPane: View {
    @Bindable var settings: LanguageSettings
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
        }
        .settingsPane()
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

private struct ExclusionsPane: View {
    var excludedApps = ExcludedApps.shared

    /// Bundle IDs of running regular apps that can still be excluded.
    @State private var runningApps: [String] = []

    var body: some View {
        Form {
            Section {
                if excludedApps.bundleIDs.isEmpty {
                    Text(L10n.noExcludedApps)
                        .foregroundStyle(.secondary)
                }
                ForEach(excludedApps.bundleIDs, id: \.self) { bundleID in
                    let name = AppInfo.name(for: bundleID)
                    HStack(spacing: 8) {
                        Image(nsImage: AppInfo.icon(for: bundleID))
                        Text(name)
                        Spacer()
                        Button {
                            excludedApps.setExcluded(false, bundleID: bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.removeApp(name))
                    }
                }
                addAppMenu
            } footer: {
                Text(L10n.excludedAppsFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onAppear(perform: refreshRunningApps)
        // Other apps may have launched or quit meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRunningApps()
        }
    }

    private var addAppMenu: some View {
        Menu {
            let candidates = runningApps.filter { !excludedApps.contains($0) }
            if !candidates.isEmpty {
                Section(L10n.runningApps) {
                    ForEach(candidates, id: \.self) { bundleID in
                        Button {
                            excludedApps.setExcluded(true, bundleID: bundleID)
                        } label: {
                            Label {
                                Text(AppInfo.name(for: bundleID))
                            } icon: {
                                Image(nsImage: AppInfo.icon(for: bundleID))
                            }
                        }
                    }
                }
                Divider()
            }
            Button(L10n.chooseApp, action: chooseApps)
        } label: {
            Label(L10n.addApp, systemImage: "plus.circle")
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private func refreshRunningApps() {
        let ownID = Bundle.main.bundleIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != ownID }
            .sorted { AppInfo.name(for: $0).localizedStandardCompare(AppInfo.name(for: $1)) == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = L10n.addApp
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier {
                excludedApps.setExcluded(true, bundleID: bundleID)
            }
        }
    }
}

private struct ClaudePane: View {
    @Bindable var claude = ClaudeSettings.shared
    @State private var apiKeyDraft = ""

    var body: some View {
        Form {
            Section {
                apiKeyRow
                Picker(L10n.claudeModel, selection: $claude.model) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.claudeFooter)
                        .foregroundStyle(.secondary)
                    Button(L10n.getAPIKey) {
                        if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .settingsPane()
    }

    @ViewBuilder
    private var apiKeyRow: some View {
        if claude.hasAPIKey {
            LabeledContent(L10n.apiKey) {
                HStack(spacing: 10) {
                    Text(L10n.apiKeySaved)
                        .foregroundStyle(.secondary)
                    Button(L10n.remove, role: .destructive) {
                        claude.remove()
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                SecureField(L10n.apiKey, text: $apiKeyDraft, prompt: Text(verbatim: "sk-ant-…"))
                    .onSubmit(saveAPIKey)
                Button(L10n.save, action: saveAPIKey)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveAPIKey() {
        if claude.save(apiKeyDraft) {
            apiKeyDraft = ""
        }
    }
}
