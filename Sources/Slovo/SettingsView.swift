import Carbon.HIToolbox
import SwiftUI
import Translation
import UniformTypeIdentifiers

/// Settings window: one tab per area, so the window stays as tall as the open tab needs.
struct SettingsView: View {
    private enum Tab: String {
        case general, languages, exclusions, ai
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
            SwiftUI.Tab("AI", systemImage: "sparkles", value: Tab.ai) {
                AIPane()
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
    var hotKeys = HotKeySettings.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.selectedTextShortcut) {
                    HotKeyRecorder(action: .selection, hotKeys: hotKeys)
                }
                LabeledContent(L10n.screenAreaShortcut) {
                    HotKeyRecorder(action: .screenArea, hotKeys: hotKeys)
                }
                LabeledContent(L10n.translateOnScreen) {
                    HotKeyRecorder(action: .screenOverlay, hotKeys: hotKeys)
                }
                LabeledContent(L10n.composeShortcut) {
                    HotKeyRecorder(action: .compose, hotKeys: hotKeys)
                }
            } header: {
                Text(L10n.shortcuts)
            }
            Section {
                Toggle(L10n.openAtLogin, isOn: $controller.launchAtLogin)
            }
        }
        .settingsPane()
    }
}

/// Click, then press the new shortcut: Esc cancels, Delete removes it, and for the selection
/// ⌘C pressed twice brings back ⌘C C.
private struct HotKeyRecorder: View {
    let action: HotKeySettings.Action
    let hotKeys: HotKeySettings

    @State private var monitor: Any?
    @State private var problem: String?
    @State private var hint: String?
    /// When ⌘C was pressed while recording the selection's shortcut, waiting for the second press.
    @State private var firstCopyAt: TimeInterval?

    private var isRecording: Bool {
        hotKeys.recordingAction == action
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if hotKeys.shortcutDisplay(for: action) != nil, !isRecording {
                    Button {
                        problem = nil
                        _ = hotKeys.assign(nil, to: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L10n.clearShortcut)
                    .accessibilityLabel(L10n.clearShortcut)
                }
                Button(action: toggleRecording) {
                    Text(isRecording ? L10n.pressShortcut : hotKeys.shortcutDisplay(for: action) ?? L10n.notSet)
                        .foregroundStyle(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .frame(minWidth: 120)
                }
            }
            if let message = problem ?? hotKeys.registrationErrors[action] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isRecording {
                // Only while recording, right where it's needed, instead of a paragraph under the section.
                Text(hint ?? L10n.recordingHint(for: action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Another recorder took over, or recording ended.
        .onChange(of: hotKeys.recordingAction) { _, recording in
            if recording != action { removeMonitor() }
        }
        .onDisappear(perform: stopRecording)
        // Global shortcuts stay off while recording; don't leave them off when the user switches apps.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        problem = nil
        hint = nil
        firstCopyAt = nil
        hotKeys.recordingAction = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let keyCode = Int(event.keyCode)
        let isPlain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        let combo = KeyCombo(event: event)
        let isCommandC = combo == KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))

        if action == .selection && isCommandC {
            // ⌘C on its own isn't allowed as a global shortcut, but ⌘C twice is the default.
            if let firstCopyAt, event.timestamp - firstCopyAt <= DoubleCopyMonitor.maxInterval {
                hotKeys.assignDoubleCopy()
                problem = nil
                stopRecording()
            } else {
                firstCopyAt = event.timestamp
                problem = nil
                hint = L10n.pressCommandCAgain
            }
            return
        }
        firstCopyAt = nil
        hint = nil

        if isPlain && keyCode == kVK_Escape {
            stopRecording()
        } else if isPlain && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            problem = nil
            _ = hotKeys.assign(nil, to: action)
            stopRecording()
        } else if let problem = hotKeys.assign(combo, to: action) {
            self.problem = problem
            NSSound.beep()
        } else {
            problem = nil
            stopRecording()
        }
    }

    private func stopRecording() {
        removeMonitor()
        if isRecording { hotKeys.recordingAction = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
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

private struct AIPane: View {
    @Bindable var settings = AISettings.shared
    @State private var keyDraft = ""
    /// Models offered by the OpenAI-compatible server, for the model field's list.
    @State private var models: [String] = []
    @State private var claudeModels: [ClaudeModel] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?

    var body: some View {
        Form {
            Section {
                Picker(L10n.aiProvider, selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
            }
            switch settings.provider {
            case .claude: claudeSection
            case .openAICompatible: openAISection
            }
        }
        .settingsPane()
        // A half-typed key belongs to the provider it was typed for.
        .onChange(of: settings.provider) { keyDraft = "" }
    }

    private var claudeSection: some View {
        Section {
            keyRow(for: .claude, placeholder: "sk-ant-…")
            if settings.hasClaudeKey {
                LabeledContent(L10n.claudeModel) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            if isLoadingModels {
                                ProgressView().controlSize(.small)
                            }
                            Picker(L10n.claudeModel, selection: claudeModelSelection) {
                                ForEach(claudeModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                                // The saved model while the list loads, or if it failed to.
                                if !settings.claudeModel.isEmpty, !claudeModels.contains(where: { $0.id == settings.claudeModel }) {
                                    Text(verbatim: settings.claudeModel).tag(settings.claudeModel)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if let modelsError {
                            Text(modelsError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
        .task(id: settings.hasClaudeKey) {
            await loadClaudeModels()
        }
    }

    private var claudeModelSelection: Binding<String> {
        Binding {
            settings.claudeModel
        } set: { id in
            if let model = claudeModels.first(where: { $0.id == id }) {
                settings.selectClaudeModel(model)
            }
        }
    }

    private func loadClaudeModels() async {
        guard let key = settings.claudeKey else {
            claudeModels = []
            modelsError = nil
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let loaded = try await ClaudeTranslator.models(apiKey: key)
            guard !Task.isCancelled else { return }
            claudeModels = loaded
            modelsError = loaded.isEmpty ? L10n.aiNoModels : nil
            // Newest first: a fresh setup, or a model the account no longer offers, gets the newest one.
            if let newest = loaded.first, !loaded.contains(where: { $0.id == settings.claudeModel }) {
                settings.selectClaudeModel(newest)
            }
        } catch {
            guard !Task.isCancelled else { return }
            claudeModels = []
            modelsError = L10n.aiModelsFailed(error.localizedDescription)
        }
    }

    private var openAISection: some View {
        Section {
            TextField(L10n.apiAddress, text: $settings.openAIBaseURL, prompt: Text(verbatim: AISettings.defaultOpenAIBaseURL))
            keyRow(for: .openAICompatible, placeholder: L10n.optionalKey)
            LabeledContent(L10n.claudeModel) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        }
                        ModelComboBox(text: $settings.openAIModel, items: models, placeholder: "model-name")
                            .frame(width: 240)
                    }
                    if let modelsError {
                        Text(modelsError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text(L10n.openAIFooter)
                .foregroundStyle(.secondary)
        }
        // Reload when the address or the key changes, after a pause so typing doesn't fire a request per key.
        .task(id: "\(settings.openAIBaseURL)|\(settings.hasOpenAIKey)") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadModels()
        }
    }

    private func loadModels() async {
        guard let url = settings.openAIModelsURL else {
            models = []
            modelsError = nil
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let loaded = try await OpenAICompatibleTranslator.models(at: url, apiKey: settings.openAIKey)
            guard !Task.isCancelled else { return }
            models = loaded
            modelsError = loaded.isEmpty ? L10n.aiNoModels : nil
        } catch {
            guard !Task.isCancelled else { return }
            models = []
            modelsError = L10n.aiModelsFailed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func keyRow(for provider: AIProvider, placeholder: String) -> some View {
        let hasKey = provider == .claude ? settings.hasClaudeKey : settings.hasOpenAIKey
        if hasKey {
            LabeledContent(L10n.apiKey) {
                HStack(spacing: 10) {
                    Text(L10n.apiKeySaved)
                        .foregroundStyle(.secondary)
                    Button(L10n.remove, role: .destructive) {
                        settings.removeKey(for: provider)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                SecureField(L10n.apiKey, text: $keyDraft, prompt: Text(verbatim: placeholder))
                    .onSubmit { saveKey(for: provider) }
                Button(L10n.save) { saveKey(for: provider) }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveKey(for provider: AIProvider) {
        if settings.saveKey(keyDraft, for: provider) {
            keyDraft = ""
        }
    }
}

/// An editable field with a drop-down list: pick a model the server offers, or type any name.
/// AppKit's combo box also completes the name while typing, handy for long lists like OpenRouter's.
private struct ModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.completes = true
        box.numberOfVisibleItems = 12
        box.delegate = context.coordinator
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.text = $text
        if (box.objectValues as? [String]) != items {
            box.removeAllItems()
            box.addItems(withObjectValues: items)
        }
        if box.stringValue != text {
            box.stringValue = text
        }
        box.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            text.wrappedValue = box.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox,
                  let selected = box.objectValueOfSelectedItem as? String else { return }
            text.wrappedValue = selected
        }
    }
}
