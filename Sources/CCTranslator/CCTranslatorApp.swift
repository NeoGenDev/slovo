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
            // A menu bar app isn't active by default, so the window would open behind others.
            NSApp.activate()
            openSettings()
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
