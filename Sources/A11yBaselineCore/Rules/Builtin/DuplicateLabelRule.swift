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
///
/// Сравниваются РЕПЛИКИ ЦЕЛИКОМ, а не подписи. Разница выяснилась на живом
/// прогоне по «Настройкам» iOS: там есть строка списка «Поиск» и поле поиска
/// «Поиск». Подписи совпадают, но VoiceOver произносит «Поиск, кнопка»
/// и «Поиск, поле поиска» — роль он объявляет сам, и на слух эти элементы
/// различимы. Правило, сравнивавшее только подписи, сообщало о дефекте там,
/// где для слушающего человека его нет.
public struct DuplicateLabelRule: Rule {

    public static let id = "duplicate-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance),
              let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }

        // Совпадать должна вся реплика: подпись плюс роль. Два элемента
        // с одинаковой подписью, но разными ролями человек различает на слух.
        let spoken = utterance.spoken.lowercased()
        let twins = context.screen.utterances.filter { other in
            other.index != utterance.index
                && context.isInteractive(other)
                && other.spoken.lowercased() == spoken
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
