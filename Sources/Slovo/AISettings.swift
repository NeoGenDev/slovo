import Foundation
import Observation
import Security

/// Where "Improve with AI" sends the text.
enum AIProvider: String, CaseIterable, Identifiable {
    case claude
    /// Any server speaking OpenAI's chat completions API: OpenAI, OpenRouter, Ollama, LM Studio…
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .openAICompatible: L10n.openAICompatible
        }
    }
}

/// Claude models offered for "Improve with AI".
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

/// An API key in the login Keychain.
struct KeychainSecret {
    let service: String
    private let account = "api-key"

    var value: String? {
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

    func save(_ value: String) -> Bool {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// "Improve with AI" settings: the provider, each provider's model, and API keys kept in the Keychain.
@Observable
final class AISettings {
    static let shared = AISettings()

    var provider: AIProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }

    var claudeModel: ClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel.rawValue, forKey: Keys.claudeModel) }
    }

    /// The API root, e.g. https://api.openai.com/v1 or http://localhost:11434/v1 for Ollama.
    var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }

    var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    private(set) var hasClaudeKey = false
    private(set) var hasOpenAIKey = false

    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

    private enum Keys {
        static let provider = "aiProvider"
        static let claudeModel = "claudeModel"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
    }

    private static let bundleID = Bundle.main.bundleIdentifier ?? "dev.slovo.app"
    private let claudeSecret = KeychainSecret(service: "\(bundleID).anthropic")
    private let openAISecret = KeychainSecret(service: "\(bundleID).openai")

    init() {
        let defaults = UserDefaults.standard
        provider = defaults.string(forKey: Keys.provider).flatMap(AIProvider.init(rawValue:)) ?? .claude
        claudeModel = defaults.string(forKey: Keys.claudeModel).flatMap(ClaudeModel.init(rawValue:)) ?? .opus
        openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? Self.defaultOpenAIBaseURL
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? ""
        hasClaudeKey = claudeSecret.value != nil
        hasOpenAIKey = openAISecret.value != nil
    }

    /// Whether the ✦ button has somewhere to send the text. Local OpenAI-compatible servers
    /// usually need no key, so only the address and model are required there.
    var isConfigured: Bool {
        switch provider {
        case .claude: hasClaudeKey
        case .openAICompatible: openAIURL != nil && !openAIModel.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var claudeKey: String? { claudeSecret.value }
    var openAIKey: String? { openAISecret.value }

    /// `…/chat/completions` under the configured root.
    var openAIURL: URL? { openAIEndpoint("chat/completions") }

    /// `…/models`, the list of models the server offers.
    var openAIModelsURL: URL? { openAIEndpoint("models") }

    /// A path under the configured root, tolerant of a trailing slash.
    private func openAIEndpoint(_ path: String) -> URL? {
        var root = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: "\(root)/\(path)"), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// The name shown after a successful rewrite: "Claude", or the OpenAI-compatible model's name.
    var improverName: String {
        switch provider {
        case .claude: "Claude"
        case .openAICompatible: openAIModel.trimmingCharacters(in: .whitespaces)
        }
    }

    @discardableResult
    func saveKey(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch provider {
        case .claude:
            hasClaudeKey = claudeSecret.save(trimmed)
            return hasClaudeKey
        case .openAICompatible:
            hasOpenAIKey = openAISecret.save(trimmed)
            return hasOpenAIKey
        }
    }

    func removeKey(for provider: AIProvider) {
        switch provider {
        case .claude:
            claudeSecret.delete()
            hasClaudeKey = false
        case .openAICompatible:
            openAISecret.delete()
            hasOpenAIKey = false
        }
    }
}
