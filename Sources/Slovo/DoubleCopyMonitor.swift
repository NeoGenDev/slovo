import AppKit
import Carbon.HIToolbox

/// Detects ⌘C pressed twice in quick succession in any app.
///
/// Matches on the physical key code, so it works with the Russian layout too.
/// Requires the Accessibility permission; without it the global monitor receives nothing.
final class DoubleCopyMonitor {
    var onTrigger: (() -> Void)?

    /// Longest pause between the two presses; the shortcut recorder uses it too.
    static let maxInterval: TimeInterval = 0.45
    private var monitor: Any?
    private var lastCopyAt: TimeInterval?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        lastCopyAt = nil
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode == UInt16(kVK_ANSI_C), modifiers == .command else {
            lastCopyAt = nil
            return
        }
        guard !event.isARepeat else { return }

        if let lastCopyAt, event.timestamp - lastCopyAt <= Self.maxInterval {
            self.lastCopyAt = nil
            onTrigger?()
        } else {
            lastCopyAt = event.timestamp
        }
    }
}
