import Foundation

/// Интерактивный элемент, у которого нечего произнести.
///
/// Самая дорогая находка из возможных: до элемента можно дойти, но человек
/// не узнает, что это. Практически всегда это иконочная кнопка, которой
/// забыли задать `accessibilityLabel`.
public struct EmptyUtteranceRule: Rule {

    public static let id = "empty-utterance"
    public static let standard = Standards.nonTextContent

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance) else { return nil }

        // Признаки в реплике не считаются содержанием: «кнопка» без подписи
        // произносится как «кнопка», и это ровно тот случай, который ловим.
        let meaningful = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard meaningful.isEmpty else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .blocker,
            screen: context.screen.screen,
            summary: "Интерактивный элемент без подписи — пользователь не узнает, что это",
            evidence: "VoiceOver произносит: «\(utterance.spoken)». Назначения элемента в реплике нет.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Button(action: submit) {\n    Image(systemName: \"paperplane\")\n}",
                after: "Button(action: submit) {\n    Image(systemName: \"paperplane\")\n}\n.accessibilityLabel(\"Отправить\")",
                note: "Подпись описывает действие, а не картинку: «Отправить», а не «Самолётик»."
            )
        )
    }
}
