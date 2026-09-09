import Foundation

/// Подпись, которая ничего не сообщает.
///
/// Отличается от пустой подписи тем, что формально она есть, поэтому
/// встроенный аудит платформы такой элемент пропускает: с точки зрения
/// проверки «есть ли описание» всё в порядке. Вред при этом тот же самый.
public struct GenericLabelRule: Rule {

    public static let id = "generic-label"
    public static let standard = Standards.nameRoleValue

    /// Слова, которые сами по себе не являются описанием.
    /// Список двуязычный: приложения российских команд часто содержат смесь.
    private static let generic: Set<String> = [
        // Роль вместо назначения
        "button", "кнопка", "image", "изображение", "картинка", "icon", "иконка",
        "view", "элемент", "item", "cell", "ячейка", "label", "текст",
        // Заглушки
        "untitled", "без названия", "unknown", "неизвестно", "placeholder",
        "todo", "test", "тест", "temp", "default", "none", "нет",
        // Пустые указания
        "нажмите", "tap", "click", "выбрать", "select", "открыть", "open",
    ]

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }

        let normalized = label.lowercased()
        guard Self.generic.contains(normalized) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            summary: "Подпись «\(label)» не описывает назначение элемента",
            evidence: "VoiceOver произносит: «\(utterance.spoken)». Человек слышит роль, но не понимает, что произойдёт при нажатии.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: ".accessibilityLabel(\"\(label)\")",
                after: ".accessibilityLabel(\"<что произойдёт при нажатии>\")",
                note: "Признак «кнопка» VoiceOver добавляет сам — дублировать его в подписи не нужно."
            )
        )
    }
}
