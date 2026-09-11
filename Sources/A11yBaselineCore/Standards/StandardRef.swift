import Foundation

/// Ссылка на пункт стандарта.
///
/// Почему клауза 11, а не 9: EN 301 549 прямо говорит, что требования клаузы 11
/// («Non-web software») и клаузы 9 («Web») никогда не применяются одновременно,
/// и что при любых сомнениях приоритет у клаузы 11. Нативное приложение — это
/// non-web software целиком, включая webview внутри него. Практическое
/// следствие: веб-методология и веб-сканеры сюда структурно не дотягиваются,
/// и это единственное место, где у нативной специализации есть формальное
/// основание, а не только опыт.
public struct StandardRef: Codable, Equatable, Sendable {

    /// Пункт EN 301 549, например «11.5.2.5».
    public var en301549: String

    /// Критерий WCAG 2.2, например «1.3.1». Необязателен: часть требований
    /// клаузы 11 не имеет веб-аналога.
    public var wcag22: String?

    /// Короткое человеческое название требования.
    public var title: String

    public init(en301549: String, wcag22: String? = nil, title: String) {
        self.en301549 = en301549
        self.wcag22 = wcag22
        self.title = title
    }
}

/// Справочник пунктов, на которые ссылаются встроенные правила.
///
/// Список намеренно короткий: сюда попадает только то, на что реально
/// ссылается хотя бы одно правило. Справочник «на всякий случай» устаревает
/// и вводит в заблуждение.
public enum Standards {

    public static let nameRoleValue = StandardRef(
        en301549: "11.5.2.5",
        wcag22: "4.1.2",
        title: "Имя, роль, значение доступны программно"
    )

    public static let infoAndRelationships = StandardRef(
        en301549: "11.1.3.1",
        wcag22: "1.3.1",
        title: "Информация и связи передаются программно"
    )

    public static let meaningfulSequence = StandardRef(
        en301549: "11.1.3.2",
        wcag22: "1.3.2",
        title: "Осмысленный порядок чтения"
    )

    public static let nonTextContent = StandardRef(
        en301549: "11.1.1.1",
        wcag22: "1.1.1",
        title: "Текстовая альтернатива нетекстовому содержимому"
    )

    public static let labelInName = StandardRef(
        en301549: "11.2.5.3",
        wcag22: "2.5.3",
        title: "Видимая надпись входит в программное имя"
    )

    public static let targetSize = StandardRef(
        en301549: "11.2.5.8",
        wcag22: "2.5.8",
        title: "Минимальный размер цели нажатия"
    )
}


/// Опознание строк, которые выглядят техническими, но являются осмысленным
/// содержимым приложения.
///
/// Живёт отдельно от правил намеренно: одну и ту же строку видят несколько
/// правил, и судить о ней они обязаны одинаково. Пока проверка на домен
/// была только в правиле имени символа, то же «objects-origin.github
/// usercontent.com» спокойно проходило через правило имени файла.
public enum TechnicalText {

    /// Доменные зоны. Список короткий намеренно: он нужен не для полноты,
    /// а чтобы отсечь частые случаи вроде «github.com».
    public static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "ru", "dev", "app", "co", "me", "info",
        "gov", "edu", "ai", "cloud", "tech", "online", "site", "xyz",
    ]

    /// Похожа ли строка на доменное имя или адрес.
    public static func looksLikeDomain(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }
        guard lower.contains("."), !lower.contains(" ") else { return false }
        guard let last = lower.split(separator: ".").last else { return false }
        return topLevelDomains.contains(String(last))
    }
}
