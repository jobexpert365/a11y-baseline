import Foundation

/// Несколько интерактивных элементов на экране звучат одинаково.
///
/// Классический случай — список карточек, где у каждой кнопка «Подробнее».
/// Глазами их различают по окружению, на слух — нечем: человек слышит
/// «Подробнее, кнопка» шесть раз подряд и не знает, к чему относится каждая.
///
/// Правило принципиально не локальное: об одном элементе судить нельзя,
/// нужен весь экран. Это и есть причина, по которой правилу передаётся
/// контекст, а не только реплика.
public struct DuplicateLabelRule: Rule {

    public static let id = "duplicate-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance),
              let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }

        // Ищем другие интерактивные элементы с той же подписью.
        let twins = context.screen.utterances.filter { other in
            other.index != utterance.index
                && context.isInteractive(other)
                && other.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == label.lowercased()
        }
        guard !twins.isEmpty else { return nil }

        // Сообщаем один раз — на первом из группы. Иначе отчёт распухает
        // шестью одинаковыми находками там, где проблема одна.
        let isFirstOfGroup = twins.allSatisfy { $0.index > utterance.index }
        guard isFirstOfGroup else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .moderate,
            screen: context.screen.screen,
            summary: "\(twins.count + 1) элемента звучат одинаково: «\(label)»",
            evidence: "Все они произносятся как «\(utterance.spoken)». На слух их невозможно различить, а глазами они различаются окружением.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Button(\"\(label)\") { open(item) }",
                after: "Button(\"\(label)\") { open(item) }\n    .accessibilityLabel(\"\(label): \\(item.title)\")",
                note: "Альтернатива без изменения подписи — объединить карточку в один элемент через .accessibilityElement(children: .combine)."
            )
        )
    }
}
