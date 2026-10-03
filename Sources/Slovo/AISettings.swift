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

/// A model from Anthropic's `GET /v1/models`, which lists what the key's account can use, newest first.
struct ClaudeModel: Identifiable, Hashable {
    let id: String
    let name: String
    /// Whether the model takes `output_config.effort` with the `low` level; older and smaller models reject it.
    let supportsLowEffort: Bool
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

    /// The model ID; empty until a model is picked, and then the newest one on the account is used.
    var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: Keys.claudeModel) }
    }

    /// The model's display name from the list, e.g. "Claude Opus 5.5", for the "Improved by" caption.
    private(set) var claudeModelName: String {
        didSet { UserDefaults.standard.set(claudeModelName, forKey: Keys.claudeModelName) }
    }

    /// Remembered with the model so a request doesn't need the model list first.
    var claudeModelSupportsLowEffort: Bool {
        didSet { UserDefaults.standard.set(claudeModelSupportsLowEffort, forKey: Keys.claudeModelSupportsLowEffort) }
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
        static let claudeModelName = "claudeModelName"
        static let claudeModelSupportsLowEffort = "claudeModelSupportsLowEffort"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
    }

    private static let bundleID = Bundle.main.bundleIdentifier ?? "dev.slovo.app"
    private let claudeSecret = KeychainSecret(service: "\(bundleID).anthropic")
    private let openAISecret = KeychainSecret(service: "\(bundleID).openai")

    init() {
        let defaults = UserDefaults.standard
        provider = defaults.string(forKey: Keys.provider).flatMap(AIProvider.init(rawValue:)) ?? .claude
        claudeModel = defaults.string(forKey: Keys.claudeModel) ?? ""
        claudeModelName = defaults.string(forKey: Keys.claudeModelName) ?? ""
        claudeModelSupportsLowEffort = defaults.object(forKey: Keys.claudeModelSupportsLowEffort) as? Bool ?? true
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

    /// The name shown after a successful rewrite: the Claude model's name ("Claude" until the model list
    /// has been seen), or the OpenAI-compatible model's ID.
    var improverName: String {
        switch provider {
        case .claude: claudeModelName.isEmpty ? "Claude" : claudeModelName
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

    func selectClaudeModel(_ model: ClaudeModel) {
        claudeModel = model.id
        claudeModelName = model.name
        claudeModelSupportsLowEffort = model.supportsLowEffort
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
