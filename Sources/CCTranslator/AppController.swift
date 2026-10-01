import AppKit
import Observation
import ServiceManagement

/// Wires the global ⌘C C shortcut to the translation popup and owns app-wide state.
@Observable
final class AppController {
    private(set) var isTrusted = Accessibility.isTrusted

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }

    @ObservationIgnored private let hotkey = DoubleCopyMonitor()
    @ObservationIgnored private let popup = PopupController()
    @ObservationIgnored private var trustTimer: Timer?

    func start() {
        hotkey.onTrigger = { [weak self] in self?.handleDoubleCopy() }

        // Dev shortcut: `open "build/CC Translator.app" --args --demo "Some text"` shows the popup at the pointer.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--demo"), arguments.indices.contains(index + 1) {
            popup.show(text: arguments[index + 1], context: SelectionContext(app: nil, isEditable: true, selectionRect: nil))
        }

        if isTrusted {
            hotkey.start()
        } else {
            Accessibility.prompt()
            watchForTrust()
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
        hotkey.start()
    }

    private func handleDoubleCopy() {
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
            NSLog("CC Translator: failed to update login item: \(error)")
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
