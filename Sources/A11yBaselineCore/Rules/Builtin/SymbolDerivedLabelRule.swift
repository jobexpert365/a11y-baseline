import Foundation

/// Подпись, в которую утекло имя SF Symbol.
///
/// Точное правило: имена символов Apple пишутся строчными буквами и обычно
/// содержат точки — `chevron.forward`, `square.and.arrow.up`,
/// `calendar.day.timeline.leading`. Такая строка не может быть текстом
/// для человека ни на одном языке, поэтому ложных срабатываний здесь
/// практически нет.
///
/// Найдено прогоном по «Календарю» iOS: там есть кнопка с подписью
/// `calendar.day.timeline.leading`. Прошлая версия правила это ПРОПУСКАЛА
/// (точки не проходили проверку «только буквы») и одновременно обвиняла
/// бренд «Sonava» в «Быстрых командах». То есть ошибалась в обе стороны
/// сразу — и молчала там, где надо было говорить, и говорила там, где
/// надо было молчать.
public struct SymbolNameLabelRule: Rule {

    public static let id = "symbol-name-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.looksLikeSymbolName(label) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            summary: "В подпись попало имя символа: «\(label)»",
            evidence: "VoiceOver произносит «\(utterance.spoken)». Это идентификатор SF Symbol из кода, а не текст для человека.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Image(systemName: \"\(label)\")",
                after: "Image(systemName: \"\(label)\")\n    .accessibilityLabel(\"<назначение элемента>\")",
                note: "Если элемент декоративный — уберите его из дерева: .accessibilityHidden(true)."
            )
        )
    }

    /// Форма имени SF Symbol: строчные латинские буквы, цифры и точки,
    /// минимум одна точка.
    ///
    /// Точка обязательна намеренно. Без неё под правило попадали бы обычные
    /// английские слова («send», «trash»), а они бывают и осмысленными
    /// подписями, и брендами. Односоставные имена символов правило пропустит —
    /// это осознанный размен точности на молчание.
    static func looksLikeSymbolName(_ label: String) -> Bool {
        guard label.contains("."), !label.contains(" "), label.count >= 5 else { return false }
        guard label.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }) else {
            return false
        }

        // Обязательна хотя бы одна буква. Без этой проверки под правило
        // попадала дата «01.01.2001» из «Сообщений»: цифры и точки, всё
        // как у имени символа. Имена SF Symbol всегда содержат слова,
        // а строка из одних цифр — это дата, версия или номер.
        guard label.contains(where: { $0.isLowercase }) else { return false }

        // Доменное имя тоже состоит из строчных слов через точку.
        // Найдено прогоном по Pulse — это сетевой логгер, он показывает
        // адреса серверов, и «github.com» попало в отчёт как дефект.
        // Отличаем по последней части: у домена это доменная зона,
        // а имена символов заканчиваются обычными словами вроде
        // «forward», «closed» или «up».
        guard !TechnicalText.looksLikeDomain(label) else { return false }

        return true
    }
}
