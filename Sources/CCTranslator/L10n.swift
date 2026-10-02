import Foundation

/// UI strings: Russian when it's the user's primary language, English otherwise.
///
/// `Locale.preferredLanguages` also reflects a per-app language picked in
/// System Settings → General → Language & Region → Applications.
/// Immutable strings and pure functions, so usable from any isolation (e.g. `LocalizedError`).
nonisolated enum L10n {
    static let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    /// Locale for language names and other system-provided text in the UI.
    static let locale = Locale(identifier: isRussian ? "ru" : "en")

    private static func pick(_ russian: String, _ english: String) -> String {
        isRussian ? russian : english
    }

    // Menu bar
    static let shortcutHint = pick("⌘C C — перевести выделенное", "⌘C C — translate selection")
    static let allowAccessibility = pick("Разрешить Универсальный доступ…", "Allow Accessibility Access…")
    static let settings = pick("Настройки…", "Settings…")
    static let history = pick("История переводов", "Translation History")
    static let historyEmpty = pick("Пока пусто", "No translations yet")
    static let historyHint = pick("Удерживайте ⌥, чтобы скопировать оригинал", "Hold ⌥ to copy the original")
    static let copyOriginal = pick("Скопировать оригинал", "Copy original")
    static let clearHistory = pick("Очистить историю", "Clear History")
    static let quit = pick("Выйти", "Quit")

    // Settings
    static let translation = pick("Перевод", "Translation")
    static let myLanguage = pick("Мой язык", "My language")
    static let downloadedLanguages = pick("Скачанные языки", "Downloaded languages")
    static let nothingDownloaded = pick("Пока ничего не скачано", "Nothing downloaded yet")
    static let downloadLanguage = pick("Скачать язык", "Download Language")
    static let manageInSystemSettings = pick("Управлять в Системных настройках…", "Manage in System Settings…")
    static let downloadedFooter = pick(
        "Скачанные языки работают офлайн. Удалить их можно в Системных настройках → Основные → Язык и регион → Языки перевода.",
        "Downloaded languages work offline. To remove them, go to System Settings → General → Language & Region → Translation Languages."
    )

    static func removeApp(_ name: String) -> String {
        pick("Убрать «\(name)»", "Remove \(name)")
    }

    static func disableIn(_ name: String) -> String {
        pick("Отключить в «\(name)»", "Disable in \(name)")
    }

    static func myLanguageFooter(lastForeign: String) -> String {
        pick(
            "Текст на любом другом языке переводится на мой. Текст на моём языке — на язык последнего перевода (сейчас \(lastForeign)).",
            "Text in any other language is translated into mine. Text in mine goes into the language of the last translation (now \(lastForeign))."
        )
    }
    static let excludedApps = pick("Исключения", "Excluded Apps")
    static let excludedAppsFooter = pick(
        "В этих приложениях ⌘C C не открывает перевод — например, в терминале или редакторе кода.",
        "⌘C C doesn't open the translator in these apps — for example, a terminal or code editor."
    )
    static let noExcludedApps = pick("Нет исключений", "No excluded apps")
    static let addApp = pick("Добавить приложение", "Add App")
    static let runningApps = pick("Запущенные", "Running")
    static let chooseApp = pick("Выбрать…", "Choose…")
    static let apiKey = pick("API-ключ", "API key")
    static let apiKeySaved = pick("Сохранён в Связке ключей", "Saved in Keychain")
    static let save = pick("Сохранить", "Save")
    static let remove = pick("Удалить", "Remove")
    static let getAPIKey = pick("Получить ключ в Anthropic Console…", "Get a key in Anthropic Console…")
    static let claudeModel = pick("Модель", "Model")
    static let claudeOpusTitle = pick("Claude Opus 5.5 — точнее всего", "Claude Opus 5.5 — most accurate")
    static let claudeSonnetTitle = pick("Claude Sonnet 5.5 — быстрее", "Claude Sonnet 5.5 — faster")
    static let claudeHaikuTitle = pick("Claude Haiku 4.5 — самая быстрая", "Claude Haiku 4.5 — fastest")
    static let claudeFooter = pick(
        "Кнопка ✦ в попапе (⌘I) отправляет оригинал и перевод в Anthropic, и выбранная модель переписывает перевод естественнее. Запросы оплачиваются по тарифам Anthropic API.",
        "The ✦ button in the popup (⌘I) sends the original and the translation to Anthropic, and the selected model rewrites the translation to read more naturally. Requests are billed at Anthropic API rates."
    )
    static let general = pick("Общие", "General")
    static let shortcut = pick("Сочетание клавиш", "Shortcut")
    static let openAtLogin = pick("Открывать при входе", "Open at Login")

    // Popup
    static let close = pick("Закрыть", "Close")
    static let improveWithClaude = pick("Улучшить через Claude (⌘I)", "Improve with Claude (⌘I)")
    static let improvedByClaude = pick("Улучшено Claude", "Improved by Claude")
    static let speakOriginal = pick("Озвучить оригинал", "Speak Original")
    static let speakTranslation = pick("Озвучить перевод", "Speak Translation")
    static let stopSpeaking = pick("Остановить озвучку", "Stop Speaking")
    static let openInDictionary = pick("Открыть в Словаре", "Open in Dictionary")
    static let britishEnglish = pick("брит.", "UK")
    static let americanEnglish = pick("амер.", "US")
    static let translateTo = pick("Перевести на", "Translate to")
    static let otherLanguages = pick("Другие языки", "Other languages")
    static let sourceLanguage = pick("Язык оригинала", "Source language")
    static let translating = pick("Переводим…", "Translating…")
    static let copy = pick("Копировать", "Copy")
    static let copied = pick("Скопировано", "Copied")
    static let replace = pick("Заменить", "Replace")
    static let readOnlyField = pick("Поле только для чтения", "Read-only field")
    static let languagesNeeded = pick("Нужно скачать языки", "Languages need to be downloaded")
    static let downloadExplanation = pick(
        "Это делается один раз — дальше перевод работает офлайн, прямо на Mac.",
        "It's a one-time download — after that, translation works offline, right on your Mac."
    )
    static let notNow = pick("Не сейчас", "Not Now")
    static let download = pick("Скачать", "Download")
    static let downloading = pick("Скачивание…", "Downloading…")

    // Errors
    static let couldNotDetectLanguage = pick(
        "Не удалось определить язык текста",
        "Couldn't detect the language of the text"
    )
    static let languagesNotDownloaded = pick(
        "Языки не скачаны. Их можно добавить в Настройках → Основные → Язык и регион.",
        "Languages weren't downloaded. You can add them in System Settings → General → Language & Region."
    )
    static let directionUnsupported = pick(
        "Это направление перевода не поддерживается",
        "This translation direction isn't supported"
    )
    static let translationUnavailable = pick("Перевод сейчас недоступен", "Translation is unavailable right now")
    static let claudeInvalidKey = pick(
        "Неверный API-ключ Anthropic. Проверьте его в настройках.",
        "The Anthropic API key is invalid. Check it in Settings."
    )
    static let claudeRateLimited = pick("Слишком много запросов к Claude. Попробуйте чуть позже.", "Too many requests to Claude. Try again shortly.")
    static let claudeOverloaded = pick("Claude сейчас перегружен. Попробуйте ещё раз.", "Claude is overloaded right now. Try again.")
    static let claudeRefused = pick("Claude отказался обрабатывать этот текст.", "Claude declined to process this text.")
    static let claudeEmptyResponse = pick("Claude вернул пустой ответ.", "Claude returned an empty response.")

    static func claudeNetworkError(_ reason: String) -> String {
        pick("Не удалось связаться с Claude: \(reason)", "Couldn't reach Claude: \(reason)")
    }

    static func claudeError(_ message: String) -> String {
        pick("Ошибка Claude: \(message)", "Claude error: \(message)")
    }

    static func translationFailed(_ reason: String) -> String {
        pick("Не удалось перевести: \(reason)", "Couldn't translate: \(reason)")
    }
}
