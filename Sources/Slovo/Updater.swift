import AppKit
import Sparkle

/// Updates from GitHub Releases. Sparkle reads the appcast attached to the latest release and, as
/// Slovo has no Developer ID, trusts a download only if its EdDSA signature matches `SUPublicEDKey`.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        // A menu bar app isn't active by default, so the update window would open behind others.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Without a Dock icon there's nothing to badge: scheduled checks show their alert without stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
