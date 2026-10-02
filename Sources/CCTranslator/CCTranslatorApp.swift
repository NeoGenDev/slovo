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
