import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut as Carbon registers it: a virtual key code plus a Carbon modifier mask.
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let screenAreaDefault = KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
    static let composeDefault = KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        modifiers = UInt32(mask)
    }

    private func has(_ modifier: Int) -> Bool {
        modifiers & UInt32(modifier) != 0
    }

    private var isFunctionKey: Bool {
        Self.functionKeys[Int(keyCode)] != nil
    }

    /// A global shortcut takes the keystroke from every app, so ⌘ plus a single key (⌘C, ⌘V…)
    /// or a bare letter is refused; function keys are fine on their own.
    var validationProblem: String? {
        if isFunctionKey { return nil }
        if has(controlKey) || has(optionKey) || (has(cmdKey) && has(shiftKey)) { return nil }
        return L10n.hotKeyNeedsModifier
    }

    /// "⌃⌥⇧⌘K", modifiers in the order macOS menus use.
    var displayString: String {
        var symbols = ""
        if has(controlKey) { symbols += "⌃" }
        if has(optionKey) { symbols += "⌥" }
        if has(shiftKey) { symbols += "⇧" }
        if has(cmdKey) { symbols += "⌘" }
        return symbols + keyName
    }

    private var keyName: String {
        if let name = Self.functionKeys[Int(keyCode)] ?? Self.specialKeys[Int(keyCode)] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// For showing the shortcut next to a menu item; nil for keys SwiftUI can't name (F-keys).
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch Int(keyCode) {
        case kVK_Return: key = .return
        case kVK_Tab: key = .tab
        case kVK_Space: key = .space
        case kVK_Delete: key = .delete
        case kVK_ForwardDelete: key = .deleteForward
        case kVK_Escape: key = .escape
        case kVK_LeftArrow: key = .leftArrow
        case kVK_RightArrow: key = .rightArrow
        case kVK_UpArrow: key = .upArrow
        case kVK_DownArrow: key = .downArrow
        case kVK_Home: key = .home
        case kVK_End: key = .end
        case kVK_PageUp: key = .pageUp
        case kVK_PageDown: key = .pageDown
        default:
            guard !isFunctionKey, let character = Self.character(for: keyCode)?.first else { return nil }
            key = KeyEquivalent(character)
        }
        // Carbon also defines an `EventModifiers`, hence the module prefix.
        var eventModifiers: SwiftUI.EventModifiers = []
        if has(cmdKey) { eventModifiers.insert(.command) }
        if has(optionKey) { eventModifiers.insert(.option) }
        if has(controlKey) { eventModifiers.insert(.control) }
        if has(shiftKey) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }

    /// The character the key types on the current Latin layout, so a shortcut reads "⌥D"
    /// rather than "⌥В" while the Russian layout is active.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: L10n.spaceKey, kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}
