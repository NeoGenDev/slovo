import SwiftUI

@main
struct CCTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller)
        } label: {
            Image(systemName: appDelegate.controller.isTrusted ? "translate" : "exclamationmark.triangle")
        }

        Settings {
            SettingsView(settings: .shared, controller: appDelegate.controller, catalog: .shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

private struct MenuContent: View {
    @Bindable var controller: AppController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if controller.isTrusted {
            Text(L10n.shortcutHint)
        } else {
            Button(L10n.allowAccessibility) {
                Accessibility.openSettings()
            }
        }
        Button(L10n.translateScreenArea) {
            controller.translateScreenArea()
        }
        // Shown as a hint; the global hot key handles the keystroke itself.
        .keyboardShortcut("2", modifiers: [.command, .shift])
        if let app = controller.lastActiveApp, let bundleID = app.bundleIdentifier {
            Toggle(
                L10n.disableIn(app.localizedName ?? AppInfo.name(for: bundleID)),
                isOn: Binding(
                    get: { ExcludedApps.shared.contains(bundleID) },
                    set: { ExcludedApps.shared.setExcluded($0, bundleID: bundleID) }
                )
            )
        }
        Divider()
        HistoryMenu(history: .shared)
        Divider()
        Button(L10n.settings) {
            guard !SettingsWindow.focusIfOpen() else { return }
            // A menu bar app isn't active by default, so the window would open behind others.
            NSApp.activate()
            openSettings()
            SettingsWindow.centerWhenShown()
        }
        .keyboardShortcut(",")
        Divider()
        Button(L10n.quit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Recent translations: a click copies the translation, ⌥-click the original.
private struct HistoryMenu: View {
    let history: TranslationHistory

    var body: some View {
        Menu(L10n.history) {
            if history.entries.isEmpty {
                Text(L10n.historyEmpty)
            } else {
                ForEach(history.entries) { entry in
                    Button {
                        Pasteboard.setString(entry.translation)
                    } label: {
                        Text(Self.menuLine(entry.translation))
                        Text(Self.menuLine(entry.source))
                    }
                    .modifierKeyAlternate(.option) {
                        Button {
                            Pasteboard.setString(entry.source)
                        } label: {
                            Text(Self.menuLine(entry.source))
                            Text(L10n.copyOriginal)
                        }
                    }
                }
                Divider()
                Text(L10n.historyHint)
                Button(L10n.clearHistory) {
                    history.clear()
                }
            }
        }
    }

    /// Menus neither wrap nor truncate titles, so long or multi-line text is cut to one short line.
    private static func menuLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }
}

/// SwiftUI opens Settings where macOS last left it, which is often at the top of the screen.
private enum SettingsWindow {
    /// `openSettings()` leaves an already open window where it is, often behind other apps' windows,
    /// so bring it forward ourselves, restoring it from the Dock if it was minimized.
    static func focusIfOpen() -> Bool {
        guard let window = find(), window.isVisible || window.isMiniaturized else { return false }
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative since macOS 14 and can be declined; this still raises the window.
        window.orderFrontRegardless()
        return true
    }

    /// The window appears a moment after `openSettings()`, so wait for it before centering.
    static func centerWhenShown() {
        Task {
            for _ in 0..<25 {
                if let window = find(), window.isVisible {
                    window.layoutIfNeeded()
                    center(window)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private static func find() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
            // The popup panel and menu bar windows are untitled, so the titled one is Settings.
            ?? NSApp.windows.first { $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
    }

    /// Share of the free vertical space left above the window; under half sits it a little above
    /// center, which reads as centered (and leaves room to grow down when a taller tab opens).
    private static let spaceAboveShare: CGFloat = 0.4

    /// Centers on the screen with the pointer: the one whose menu bar was just clicked.
    private static func center(_ window: NSWindow) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        let freeHeight = max(visible.height - size.height, 0)
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + freeHeight * (1 - spaceAboveShare)
        ))
    }
}
