import Foundation
import Observation
import Security

/// Claude models offered for "Improve with Claude".
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: L10n.claudeOpusTitle
        case .sonnet: L10n.claudeSonnetTitle
        case .haiku: L10n.claudeHaikuTitle
        }
    }

    /// `output_config.effort` and server-side `fallbacks` exist on the 5.x models;
    /// Haiku 4.5 rejects `effort` with a 400 and has no fallback models.
    var supportsEffortAndFallbacks: Bool {
        self != .haiku
    }
}

/// "Improve with Claude" settings: the model, and the Anthropic API key kept in the login Keychain.
@Observable
final class ClaudeSettings {
    static let shared = ClaudeSettings()

    private(set) var hasAPIKey = false

    var model: ClaudeModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey) }
    }

    private static let service = "\(Bundle.main.bundleIdentifier ?? "dev.slovo.app").anthropic"
    private static let account = "api-key"
    private static let modelKey = "claudeModel"

    init() {
        model = UserDefaults.standard.string(forKey: Self.modelKey).flatMap(ClaudeModel.init(rawValue:)) ?? .opus
        hasAPIKey = Self.loadKey() != nil
    }

    var apiKey: String? { Self.loadKey() }

    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        Self.deleteKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        let saved = SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        hasAPIKey = saved
        return saved
    }

    func remove() {
        Self.deleteKey()
        hasAPIKey = false
    }

    private static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
