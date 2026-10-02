import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement

/// Wires the global shortcuts to the translation popup and owns app-wide state.
@Observable
final class AppController {
    private(set) var isTrusted = Accessibility.isTrusted

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }

    /// The app the user was in before opening the menu bar menu, for its "Disable in…" item.
    private(set) var lastActiveApp: NSRunningApplication?

    @ObservationIgnored private let hotkey = DoubleCopyMonitor()
    @ObservationIgnored private let popup = PopupController()
    @ObservationIgnored private let overlay = ScreenOverlayController()
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private let hotKeys = HotKeySettings.shared
    @ObservationIgnored private var registeredHotKeys: [HotKeySettings.Action: GlobalHotKey] = [:]
    /// The frontmost app is on the excluded list, so the registered shortcuts are off for now.
    @ObservationIgnored private var frontmostIsExcluded = false
    @ObservationIgnored private var isCapturingScreen = false

    func start() {
        hotkey.onTrigger = { [weak self] in self?.handleDoubleCopy() }
        overlay.onNoText = { [weak self] in self?.popup.showFailure(L10n.noTextFound) }
        overlay.onNeedsPopup = { [weak self] text in
            self?.popup.show(text: text, context: SelectionContext(app: nil, isEditable: false, selectionRect: nil, source: .screen))
        }
        overlay.onClosed = { [weak self] in self?.popup.showAgainIfPinned() }
        hotKeys.onChange = { [weak self] in self?.applyHotKeys() }
        ExcludedApps.shared.onChange = { [weak self] in
            self?.updateExclusion(for: NSWorkspace.shared.frontmostApplication)
        }
        applyHotKeys()
        trackActiveApp()

        // Load the language list up front so the first popup doesn't wait for it.
        Task {
            await LanguageCatalog.shared.load()
            LanguageSettings.shared.adopt(supported: LanguageCatalog.shared.keys)
        }

        // Dev shortcuts: `open build/Slovo.app --args --demo "Some text"` shows the popup at the pointer,
        // `--compose` the writing popup.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--demo"), arguments.indices.contains(index + 1) {
            popup.show(text: arguments[index + 1], context: SelectionContext(app: nil, isEditable: true, selectionRect: nil))
        } else if arguments.contains("--compose") {
            popup.compose(context: SelectionContext(app: nil, isEditable: true, selectionRect: nil))
        }

        if !isTrusted {
            Accessibility.prompt()
            watchForTrust()
        }
    }

    /// (Re)registers the shortcuts from `HotKeySettings`: at launch, whenever they change, with none
    /// while a new one is being recorded, and with none while an excluded app is in front.
    private func applyHotKeys() {
        for hotKey in registeredHotKeys.values { hotKey.unregister() }
        registeredHotKeys = [:]
        let isRecording = hotKeys.recordingAction != nil

        if hotKeys.doubleCopyEnabled && isTrusted && !isRecording {
            hotkey.start()
        } else {
            hotkey.stop()
        }

        // A registered shortcut takes the keystroke from every app, so in an excluded app it's
        // unregistered rather than ignored: the app gets the keys as if Slovo weren't running.
        // (⌘C C only listens, so it checks the exclusion when it fires instead.)
        guard !frontmostIsExcluded else { return }

        var errors: [HotKeySettings.Action: String] = [:]
        if !isRecording {
            for action in HotKeySettings.Action.allCases {
                guard let combo = hotKeys.combo(for: action) else { continue }
                if let hotKey = GlobalHotKey(combo: combo, action: { [weak self] in self?.perform(action) }) {
                    registeredHotKeys[action] = hotKey
                } else {
                    errors[action] = L10n.hotKeyTaken
                }
            }
        }
        hotKeys.registrationErrors = errors
    }

    private func perform(_ action: HotKeySettings.Action) {
        switch action {
        case .selection: translateSelection()
        case .screenArea: translateScreenArea()
        case .screenOverlay: translateOnScreen()
        case .compose: compose()
        }
    }

    /// An empty popup to write in. Insert pastes the translation where the caret was, so the popup
    /// opens under it; inserting needs the same Accessibility permission as Replace.
    func compose() {
        guard isTrusted else {
            Accessibility.prompt()
            return
        }
        popup.compose(context: SelectionInspector.capture())
    }

    /// The custom selection shortcut: copies the selection itself, then translates it like ⌘C C.
    /// Excluded apps don't apply: they guard against accidental double copies, and this is deliberate.
    func translateSelection() {
        guard isTrusted else {
            Accessibility.prompt()
            return
        }
        let context = SelectionInspector.capture()
        Task {
            guard let text = await SelectionCopier.copySelection(),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                return
            }
            popup.show(text: text, context: context)
        }
    }

    /// macOS has no notification for the Accessibility grant, so poll until the user flips the switch.
    private func watchForTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        }
    }

    private func refreshTrust() {
        guard Accessibility.isTrusted else { return }
        isTrusted = true
        trustTimer?.invalidate()
        trustTimer = nil
        applyHotKeys()
    }

    /// Lets the user pick an area of the screen, recognizes its text and translates it in the popup.
    func translateScreenArea() {
        guard !isCapturingScreen else { return }
        isCapturingScreen = true
        // An open popup would otherwise end up in the picture.
        popup.hideForScreenCapture()
        Task {
            defer { isCapturingScreen = false }
            switch await ScreenTextCapture.run() {
            case .text(let text):
                popup.show(text: text, context: SelectionContext(app: nil, isEditable: false, selectionRect: nil, source: .screen))
            case .noText:
                popup.showFailure(L10n.noTextFound)
            case .cancelled, .needsPermission:
                popup.showAgainIfPinned()
            }
        }
    }

    /// Pick an area like ⇧⌘2, then see the translation drawn over the original text in place.
    func translateOnScreen() {
        guard !isCapturingScreen, ScreenTextCapture.ensurePermission() else { return }
        isCapturingScreen = true
        popup.hideForScreenCapture()
        overlay.close()
        Task {
            defer { isCapturingScreen = false }
            let picker = RegionPicker()
            guard let area = await picker.pick() else {
                popup.showAgainIfPinned()
                return
            }
            await overlay.show(area: area)
        }
    }

    private func trackActiveApp() {
        noteActivation(of: NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.noteActivation(of: app) }
        }
    }

    private func noteActivation(of app: NSRunningApplication?) {
        updateExclusion(for: app)
        // Our own Settings window activating us isn't an app the user would want to exclude.
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastActiveApp = app
    }

    private func updateExclusion(for app: NSRunningApplication?) {
        let excluded = app?.bundleIdentifier.map(ExcludedApps.shared.contains) ?? false
        guard excluded != frontmostIsExcluded else { return }
        frontmostIsExcluded = excluded
        applyHotKeys()
    }

    private func handleDoubleCopy() {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           ExcludedApps.shared.contains(bundleID) {
            return
        }
        // Inspect the focused element right away, while the source app still owns focus.
        let context = SelectionInspector.capture()
        Task {
            // The source app writes the copy asynchronously; give it a moment to land on the pasteboard.
            try? await Task.sleep(for: .milliseconds(120))
            guard let text = NSPasteboard.general.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                return
            }
            popup.show(text: text, context: context)
        }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Slovo: failed to update login item: \(error)")
        }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
