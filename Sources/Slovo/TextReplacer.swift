import AppKit
import Carbon.HIToolbox

enum Pasteboard {
    static func setString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Deep copy of every item and type, so rich text and images survive a round trip.
    static func snapshot() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

/// Replaces the selection in another app by pasting over it — the one approach that works everywhere.
enum TextReplacer {
    static func replaceSelection(with text: String, in app: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general
        let saved = Pasteboard.snapshot()
        Pasteboard.setString(text)
        let ourChange = pasteboard.changeCount

        if let app, !app.isActive { app.activate() }
        try? await Task.sleep(for: .milliseconds(60))
        postCommandV()

        // Put the user's clipboard back once the target app has read it, unless something else wrote meanwhile.
        try? await Task.sleep(for: .milliseconds(400))
        if pasteboard.changeCount == ourChange { Pasteboard.restore(saved) }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// For the custom "translate selection" shortcut: copies the selection by posting ⌘C to the
/// frontmost app, reads it, then puts the user's clipboard back as it was.
enum SelectionCopier {
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = Pasteboard.snapshot()
        let before = pasteboard.changeCount
        postCommandC()

        // Apps write the copy asynchronously; with nothing selected the pasteboard doesn't change.
        var waited = 0
        while pasteboard.changeCount == before && waited < 300 {
            try? await Task.sleep(for: .milliseconds(15))
            waited += 15
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        Pasteboard.restore(saved)
        return text
    }

    private static func postCommandC() {
        // A private event state, so modifiers still held from the shortcut (⌥ in ⌥D) don't turn it into ⌥⌘C.
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
