import Foundation

/// UI strings: Russian when it's the user's primary language, English otherwise.
///
/// `Locale.preferredLanguages` also reflects a per-app language picked in
/// System Settings → General → Language & Region → Applications.
enum L10n {
    static let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false

    private static func pick(_ russian: String, _ english: String) -> String {
        isRussian ? russian : english
    }

    // Menu bar
    static let shortcutHint = pick("⌘C C — перевести выделенное", "⌘C C — translate selection")
    static let allowAccessibility = pick("Разрешить Универсальный доступ…", "Allow Accessibility Access…")
    static let openAtLogin = pick("Открывать при входе", "Open at Login")
    static let quit = pick("Выйти", "Quit")

    // Languages
    static let english = pick("Английский", "English")
    static let russian = pick("Русский", "Russian")

    // Popup
    static let close = pick("Закрыть", "Close")
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
    static let onlyRussianAndEnglish = pick(
        "Пока поддерживаются только русский и английский",
        "Only Russian and English are supported for now"
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
