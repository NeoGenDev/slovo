import Foundation
import Observation

/// The app's shortcuts. `AppController` re-registers them through `onChange` whenever they change.
@Observable
final class HotKeySettings {
    enum Action: CaseIterable {
        /// Translate the selected text; copies the selection itself, unlike ⌘C C.
        case selection
        case screenArea
        /// Write in your own language; the translation goes into the field you were typing in.
        case compose

        var title: String {
            switch self {
            case .selection: L10n.selectedTextShortcut
            case .screenArea: L10n.screenAreaShortcut
            case .compose: L10n.composeShortcut
            }
        }

        fileprivate var defaultsKey: String {
            switch self {
            case .selection: "hotKey.selection"
            case .screenArea: "hotKey.screenArea"
            case .compose: "hotKey.compose"
            }
        }

        fileprivate var defaultCombo: KeyCombo? {
            switch self {
            case .selection: nil
            case .screenArea: .screenAreaDefault
            case .compose: .composeDefault
            }
        }
    }

    static let shared = HotKeySettings()

    /// The selection's shortcut is ⌘C pressed twice (the default) or a combo in `combos`, never both:
    /// the shortcut field shows one of them.
    private(set) var doubleCopyEnabled: Bool {
        didSet { UserDefaults.standard.set(doubleCopyEnabled, forKey: Self.doubleCopyKey) }
    }

    private(set) var combos: [Action: KeyCombo] = [:]

    /// The shortcut being recorded. Global shortcuts are off meanwhile, so pressing the current
    /// one records it instead of firing it.
    var recordingAction: Action? {
        didSet { onChange() }
    }

    /// Filled in by `AppController` when another app already holds a shortcut.
    var registrationErrors: [Action: String] = [:]

    @ObservationIgnored var onChange: () -> Void = {}

    private static let doubleCopyKey = "doubleCopyEnabled"

    init() {
        let defaults = UserDefaults.standard
        doubleCopyEnabled = defaults.object(forKey: Self.doubleCopyKey) as? Bool ?? true
        for action in Action.allCases {
            // Stored as [keyCode, modifiers]; an empty array means the user removed the shortcut.
            if let stored = defaults.array(forKey: action.defaultsKey) as? [Int] {
                if stored.count == 2 {
                    combos[action] = KeyCombo(keyCode: UInt32(stored[0]), modifiers: UInt32(stored[1]))
                }
            } else {
                combos[action] = action.defaultCombo
            }
        }
        if doubleCopyEnabled { combos[.selection] = nil }
    }

    /// What the shortcut field shows, nil when the action has no shortcut.
    func shortcutDisplay(for action: Action) -> String? {
        if action == .selection && doubleCopyEnabled { return "⌘C C" }
        return combos[action]?.displayString
    }

    /// Back to translating the selection with ⌘C pressed twice.
    func assignDoubleCopy() {
        store(nil, for: .selection)
        doubleCopyEnabled = true
        onChange()
    }

    func combo(for action: Action) -> KeyCombo? {
        combos[action]
    }

    /// Returns why the shortcut can't be used, or nil once it's saved.
    func assign(_ combo: KeyCombo?, to action: Action) -> String? {
        if let combo {
            if let problem = combo.validationProblem { return problem }
            if let other = Action.allCases.first(where: { $0 != action && combos[$0] == combo }) {
                return L10n.hotKeyInUse(other.title)
            }
        }
        store(combo, for: action)
        if action == .selection { doubleCopyEnabled = false }
        onChange()
        return nil
    }

    private func store(_ combo: KeyCombo?, for action: Action) {
        combos[action] = combo
        UserDefaults.standard.set(combo.map { [Int($0.keyCode), Int($0.modifiers)] } ?? [], forKey: action.defaultsKey)
    }
}
