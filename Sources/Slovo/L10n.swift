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
    static let allowAccessibility = pick("Разрешить Универсальный доступ…", "Allow Accessibility Access…")
    static let translateScreenArea = pick("Перевести область экрана", "Translate Screen Area")
    static let writeAndTranslate = pick("Написать с переводом", "Write and Translate")
    static let translateOnScreen = pick("Перевести поверх экрана", "Translate on Screen")
    static let settings = pick("Настройки…", "Settings…")
    static let checkForUpdates = pick("Проверить обновления…", "Check for Updates…")
    static let checkUpdatesAutomatically = pick("Проверять обновления автоматически", "Check for Updates Automatically")
    static let history = pick("История переводов", "Translation History")
    static let historyEmpty = pick("Пока пусто", "No translations yet")
    static let historyHint = pick("Удерживайте ⌥, чтобы скопировать оригинал", "Hold ⌥ to copy the original")
    static let copyOriginal = pick("Скопировать оригинал", "Copy original")
    static let clearHistory = pick("Очистить историю", "Clear History")
    static let quit = pick("Выйти", "Quit")

    // Settings
    static let languagesTab = pick("Языки", "Languages")
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
        "В этих приложениях сочетания Slovo не работают, и нажатия достаются самому приложению — например, терминалу или редактору кода.",
        "Slovo's shortcuts are off in these apps, and the keys go to the app itself — for example, a terminal or code editor."
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
    static let aiProvider = pick("Провайдер", "Provider")
    static let openAICompatible = pick("OpenAI-совместимый API", "OpenAI-compatible API")
    static let apiAddress = pick("Адрес API", "API address")
    static let optionalKey = pick("Необязательно", "Optional")
    static let openAIFooter = pick(
        "OpenAI, OpenRouter, локальные Ollama (http://localhost:11434/v1) и LM Studio. Локальным серверам ключ не нужен.",
        "OpenAI, OpenRouter, or a local Ollama (http://localhost:11434/v1) or LM Studio. Local servers need no key."
    )
    static let claudeFooter = pick(
        "Кнопка ✦ в попапе (⌘I) отправляет оригинал и перевод в Anthropic, и выбранная модель переписывает перевод естественнее.",
        "The ✦ button in the popup (⌘I) sends the original and the translation to Anthropic, and the selected model rewrites the translation to read more naturally."
    )
    static let general = pick("Общие", "General")
    static let shortcuts = pick("Сочетания клавиш", "Shortcuts")
    static let pressCommandCAgain = pick("Нажмите ⌘C ещё раз", "Press ⌘C again")

    static func recordingHint(for action: HotKeySettings.Action) -> String {
        switch action {
        case .selection: pick("Esc — отмена · ⌘C дважды — ⌘C C", "Esc cancels · ⌘C twice for ⌘C C")
        case .screenArea, .screenOverlay, .compose: pick("Esc — отмена", "Esc cancels")
        }
    }
    static let notSet = pick("Не задано", "None")
    static let pressShortcut = pick("Нажмите сочетание…", "Press shortcut…")
    static let clearShortcut = pick("Убрать сочетание", "Remove Shortcut")
    static let spaceKey = pick("Пробел", "Space")
    static let hotKeyTaken = pick("macOS не дала назначить это сочетание, выберите другое", "macOS didn't accept this shortcut; choose another")
    static let hotKeyNeedsModifier = pick(
        "Нужен ⌃ или ⌥, либо ⇧⌘ вместе: остальные сочетания заняты приложениями и набором текста",
        "Use ⌃ or ⌥, or ⇧⌘ together: other combinations belong to apps and typing"
    )

    static func hotKeyInUse(_ title: String) -> String {
        pick("Уже назначено: «\(title)»", "Already used for \(title)")
    }

    static func selectionHint(_ shortcuts: [String]) -> String {
        pick(
            shortcuts.joined(separator: " или ") + " — перевести выделенное",
            shortcuts.joined(separator: " or ") + " — translate selection"
        )
    }
    static let selectedTextShortcut = pick("Перевести выделенное", "Translate Selection")
    static let screenAreaShortcut = translateScreenArea
    static let composeShortcut = writeAndTranslate
    static let openAtLogin = pick("Открывать при входе", "Open at Login")

    // Popup
    static let close = pick("Закрыть", "Close")
    static let pinLive = pick("Закрепить и обновлять по ходу (⌘P)", "Pin and Keep Updating (⌘P)")
    static let unpinLive = pick("Открепить (⌘P)", "Unpin (⌘P)")
    static let showOriginal = pick("Показать оригинал", "Show Original")
    static let showTranslation = pick("Показать перевод", "Show Translation")
    static let pin = pick("Закрепить (⌘P)", "Pin (⌘P)")
    static let unpin = pick("Открепить (⌘P)", "Unpin (⌘P)")
    static func improveWith(_ name: String) -> String {
        pick("Улучшить через \(name) (⌘I)", "Improve with \(name) (⌘I)")
    }

    static func improvedBy(_ name: String) -> String {
        pick("Улучшено: \(name)", "Improved by \(name)")
    }
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
    static let insert = pick("Вставить", "Insert")
    static let composePlaceholder = pick("Напишите текст", "Type to translate")
    static let readOnlyField = pick("Поле только для чтения", "Read-only field")
    static let languagesNeeded = pick("Нужно скачать языки", "Languages need to be downloaded")
    static let languageNeeded = pick("Нужно скачать язык", "A language needs to be downloaded")
    static let languageDownloaded = pick("Скачан", "Downloaded")
    static let languageMissing = pick("Не скачан", "Not downloaded")
    static let languageDownloading = pick("Скачивается…", "Downloading…")
    static let downloadExplanation = pick(
        "Это делается один раз — дальше перевод работает офлайн, прямо на Mac.",
        "It's a one-time download — after that, translation works offline, right on your Mac."
    )
    static let notNow = pick("Не сейчас", "Not Now")
    static let download = pick("Скачать…", "Download…")
    static let downloading = pick("Скачивание…", "Downloading…")
    static let waitingForConfirmation = pick("Ожидание…", "Waiting…")
    static let confirmInSystemWindow = pick(
        "Нажмите «Загрузить» в окне macOS, затем «Готово». Загрузка продолжится в фоне.",
        "Click Download in the macOS window, then Done. The download continues in the background."
    )

    // Errors
    static let noTextFound = pick("В выбранной области не найден текст", "No text found in the selected area")
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
    static let aiInvalidKey = pick("Неверный API-ключ. Проверьте его в настройках AI.", "The API key is invalid. Check it in AI settings.")
    static let aiInvalidAddress = pick("Неверный адрес API в настройках AI", "The API address in AI settings is invalid")
    static let aiRateLimited = pick("Слишком много запросов. Попробуйте чуть позже.", "Too many requests. Try again shortly.")
    static let aiOverloaded = pick("Сервис сейчас перегружен. Попробуйте ещё раз.", "The service is overloaded right now. Try again.")
    static let aiRefused = pick("Модель отказалась обрабатывать этот текст.", "The model declined to process this text.")
    static let aiNoModelList = pick("Сервер не отдал список моделей", "The server didn't return a model list")
    static let aiNoModels = pick("Сервер не предлагает ни одной модели", "The server offers no models")

    static func aiModelsFailed(_ reason: String) -> String {
        pick("Список моделей не загрузился: \(reason)", "Couldn't load models: \(reason)")
    }
    static let aiEmptyResponse = pick("Модель вернула пустой ответ.", "The model returned an empty response.")

    static func aiNetworkError(_ reason: String) -> String {
        pick("Не удалось связаться с сервисом: \(reason)", "Couldn't reach the service: \(reason)")
    }

    static func aiError(_ message: String) -> String {
        pick("Ошибка модели: \(message)", "Model error: \(message)")
    }

    static func translationFailed(_ reason: String) -> String {
        pick("Не удалось перевести: \(reason)", "Couldn't translate: \(reason)")
    }
}
