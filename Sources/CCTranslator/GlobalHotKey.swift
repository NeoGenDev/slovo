import Carbon.HIToolbox

/// A system-wide shortcut registered with the Carbon Event Manager. Unlike the ⌘C C monitor it
/// consumes the keystroke, so the frontmost app doesn't also act on it, and needs no permission.
final class GlobalHotKey {
    private static let signature: OSType = 0x4343_5452 // "CCTR"
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// `keyCode` is a `kVK_…` constant, `modifiers` a mask of `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.handle, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        // Fails with eventHotKeyExistsErr when another app already registered the same combination.
        if status != noErr {
            NSLog("CC Translator: couldn't register hot key \(keyCode) with modifiers \(modifiers): \(status)")
        }
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
