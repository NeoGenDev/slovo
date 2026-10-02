import Foundation

/// UI strings: Russian when it's the user's primary language, English otherwise.
///
/// `Locale.preferredLanguages` also reflects a per-app language picked in
/// System Settings → General → Language & Region → Applications.
enum L10n {
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
    static let general = pick("Общие", "General")
    static let shortcut = pick("Сочетание клавиш", "Shortcut")
    static let openAtLogin = pick("Открывать при входе", "Open at Login")

    // Popup
    static let close = pick("Закрыть", "Close")
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

    static func translationFailed(_ reason: String) -> String {
        pick("Не удалось перевести: \(reason)", "Couldn't translate: \(reason)")
    }
}
