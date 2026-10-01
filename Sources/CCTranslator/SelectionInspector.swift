import AppKit
import ApplicationServices

struct SelectionContext {
    var app: NSRunningApplication?
    /// Whether pasting over the selection makes sense. Unknown counts as editable.
    var isEditable: Bool
    /// Selection bounds in AppKit screen coordinates (bottom-left origin), when the app exposes them.
    var selectionRect: CGRect?
}

/// Reads the focused element of the frontmost app through the Accessibility API.
enum SelectionInspector {
    static func capture() -> SelectionContext {
        let app = NSWorkspace.shared.frontmostApplication
        guard let element = focusedElement() else {
            return SelectionContext(app: app, isEditable: true, selectionRect: nil)
        }
        return SelectionContext(app: app, isEditable: isEditable(element), selectionRect: selectionBounds(of: element))
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var answered = false
        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute] {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { continue }
            if settable.boolValue { return true }
            answered = true
        }
        // Apps with poor AX support (Electron, some games) answer nothing — don't hide Replace there.
        return !answered
    }

    private static func selectionBounds(of element: AXUIElement) -> CGRect? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0,
              let primary = NSScreen.screens.first else { return nil }

        // AX uses a top-left origin anchored to the primary screen; AppKit uses bottom-left.
        rect.origin.y = primary.frame.maxY - rect.maxY
        guard NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { return nil }
        return rect
    }
}
