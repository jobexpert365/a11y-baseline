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
    ]

    // Глаголы действия в этот список НЕ входят, и это исправление по факту.
    // Раньше здесь были «выбрать», «открыть», «select», «open» — и правило
    // обвинило кнопку «Выбрать» в приложении «Фото». Но «Выбрать» точно
    // описывает, что произойдёт при нажатии, то есть это как раз хорошая
    // подпись. Бессмысленна не краткость, а отсутствие смысла: роль вместо
    // назначения («Кнопка») или заглушка из разработки («TODO»).

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        // Судим только то, что можно нажать.
        //
        // Правило спрашивает «понятно ли, что произойдёт при нажатии»,
        // и на неинтерактивном элементе этот вопрос бессмыслен. Поймано
        // на Eureka: статический текст «None» (признаков нет вообще, нажимать
        // нечего) получил обвинение в том, что человек «не понимает, что
        // произойдёт при нажатии». А «None» там — показанное значение,
        // то есть законное содержимое.
        //
        // Замер по всему индексу: на неинтерактивных элементах правило
        // срабатывало ровно один раз на 25 приложений — этот самый случай.
        // То есть проверка ничего не стоит и убирает ложную находку целиком.
        guard context.isInteractive(utterance) else { return nil }

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
