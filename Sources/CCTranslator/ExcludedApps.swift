import AppKit
import Observation

/// Apps where ⌘C C doesn't open the translator, e.g. a terminal or code editor. Stored by bundle ID.
@Observable
final class ExcludedApps {
    static let shared = ExcludedApps()

    private(set) var bundleIDs: [String] {
        didSet { UserDefaults.standard.set(bundleIDs, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "excludedApps"

    init() {
        bundleIDs = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    func setExcluded(_ isExcluded: Bool, bundleID: String) {
        if isExcluded {
            guard !contains(bundleID) else { return }
            bundleIDs.append(bundleID)
        } else {
            bundleIDs.removeAll { $0 == bundleID }
        }
    }
}

/// Name and icon of an installed app, looked up by bundle ID.
enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// A small copy of the icon; menus and rows draw an NSImage at its own size.
    static func icon(for bundleID: String, size: CGFloat = 16) -> NSImage {
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        let resized = icon.copy() as? NSImage ?? icon
        resized.size = NSSize(width: size, height: size)
        return resized
    }
}
