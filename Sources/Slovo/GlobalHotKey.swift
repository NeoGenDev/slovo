import Carbon.HIToolbox

/// A system-wide shortcut registered with the Carbon Event Manager. Unlike the ⌘C C monitor it
/// consumes the keystroke, so the frontmost app doesn't also act on it, and needs no permission.
/// Call `unregister()` before letting go of it: the event handler holds an unretained pointer to it.
final class GlobalHotKey {
    private static let signature: OSType = 0x534C_564F // "SLVO"
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Fails when the combination is already registered in this process. macOS doesn't report
    /// clashes with other apps: their registration of the same keys succeeds as well.
    init?(combo: KeyCombo, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.handle, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else {
            NSLog("Slovo: couldn't register hot key \(combo.displayString): \(status)")
            unregister()
            return nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    /// Every registered hot key reaches every handler, so each one checks the ID it was given.
    private static let handle: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
        )
        guard status == noErr, pressedID.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
        // The address crosses into the main-actor closure as a plain integer: raw pointers aren't Sendable.
        let address = UInt(bitPattern: userData)
        // Carbon delivers hot key events on the main thread.
        return MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            guard pressedID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }
    }
}
