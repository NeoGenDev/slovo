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

    var body: some View {
        if controller.isTrusted {
            Text(L10n.shortcutHint)
        } else {
            Button(L10n.allowAccessibility) {
                Accessibility.openSettings()
            }
        }
        Divider()
        Toggle(L10n.openAtLogin, isOn: $controller.launchAtLogin)
        Divider()
        Button(L10n.quit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
