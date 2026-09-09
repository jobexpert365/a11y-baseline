import Foundation

/// Насколько находка мешает человеку.
///
/// Шкала описывает ПОСЛЕДСТВИЕ для пользователя, а не строгость нарушения
/// буквы стандарта. Так сделано потому, что покупатель отчёта решает, что
/// чинить первым, исходя из вреда, а не из номера пункта.
public enum Severity: String, Codable, Comparable, Sendable {

    /// Задачу невозможно выполнить: элемент недостижим или неозвучиваем.
    case blocker

    /// Задачу выполнить можно, но человек не понимает, что делает элемент.
    case serious

    /// Понять можно, но с усилием или лишними шагами.
    case moderate

    /// Раздражает, не мешает.
    case minor

    private var rank: Int {
        switch self {
        case .blocker: 3
        case .serious: 2
        case .moderate: 1
        case .minor: 0
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

/// Кто нашёл находку. Разделение видно в отчёте и нужно, чтобы покупатель
/// глазами видел границу между тем, что раздают бесплатно, и тем, за что
/// он платит.
public enum FindingSource: String, Codable, Sendable {

    /// Встроенный аудит платформы: `performAccessibilityAudit`.
    case platformAudit

    /// Движок правил этого пакета.
    case ruleEngine

    /// Регрессия относительно сохранённой базовой линии.
    case baselineDiff
}

/// Одна находка.
public struct Finding: Codable, Equatable, Sendable {

    /// Стабильный ключ находки: экран + правило + элемент.
    ///
    /// Стабильность важнее читаемости: по этому ключу находка помечается
    /// принятой и не всплывает на каждом прогоне. Если ключ поедет от
    /// перезапуска, механизм принятых исключений сломается.
    public var key: String

    public var ruleID: String
    public var source: FindingSource
    public var severity: Severity
    public var screen: String

    /// Что именно не так, одной фразой, языком последствия.
    public var summary: String

    /// Что человек услышит и почему это плохо.
    public var evidence: String

    /// Ссылка на пункт стандарта.
    public var standard: StandardRef?

    /// Индекс реплики в снимке экрана — чтобы отчёт мог показать контекст.
    public var utteranceIndex: Int?

    /// Парный фрагмент кода «было → стало».
    ///
    /// Это и есть то, за что платят: находку без исправления выдаёт любой
    /// сканер, а готовую правку на Swift — нет.
    public var fix: Fix?

    public init(
        key: String,
        ruleID: String,
        source: FindingSource,
        severity: Severity,
        screen: String,
        summary: String,
        evidence: String,
        standard: StandardRef? = nil,
        utteranceIndex: Int? = nil,
        fix: Fix? = nil
    ) {
        self.key = key
        self.ruleID = ruleID
        self.source = source
        self.severity = severity
        self.screen = screen
        self.summary = summary
        self.evidence = evidence
        self.standard = standard
        self.utteranceIndex = utteranceIndex
        self.fix = fix
    }

    /// Парная правка на Swift.
    public struct Fix: Codable, Equatable, Sendable {
        public var before: String
        public var after: String
        public var note: String?

        public init(before: String, after: String, note: String? = nil) {
            self.before = before
            self.after = after
            self.note = note
        }
    }
}
