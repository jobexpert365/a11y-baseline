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
        return label.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }
    }
}

/// Подпись на английском в приложении на другом языке.
///
/// Отдельное правило и намеренно СЛАБОЕ по уровню. Причина в том, что машина
/// не может отличить непереведённую подпись от названия бренда: «Send»
/// в русском приложении — скорее всего дефект, а «Sonava» — имя продукта,
/// и выглядят они одинаково.
///
/// Прогон по «Быстрым командам» это доказал: правило обвинило бренд на уровне
/// «серьёзно». Поэтому находка теперь мелкая и сформулирована как вопрос,
/// а не как обвинение: отчёт просит проверить, а не утверждает дефект.
public struct UntranslatedLabelRule: Rule {

    public static let id = "untranslated-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard !context.locale.hasPrefix("en") else { return nil }
        guard context.isInteractive(utterance) else { return nil }
        guard utterance.visibleText == nil else { return nil }

        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              label.count >= 4,
              !label.contains(" "),
              label.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .minor,
            screen: context.screen.screen,
            summary: "Проверьте подпись «\(label)»: это название или непереведённый текст?",
            evidence: "VoiceOver произносит «\(utterance.spoken)» в приложении на языке «\(context.locale)». Если это бренд — всё в порядке. Если подпись подставилась автоматически из имени символа или не переведена — человек услышит слово на чужом языке.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: ".accessibilityLabel(\"\(label)\")",
                after: ".accessibilityLabel(NSLocalizedString(\"<ключ>\", comment: \"\"))",
                note: "Названия брендов не переводятся — если это оно, находку можно принять как исключение."
            )
        )
    }
}
