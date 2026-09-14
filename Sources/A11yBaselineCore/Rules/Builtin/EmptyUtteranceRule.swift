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

        // Поле ввода без подписи, но с подсказкой, VoiceOver озвучивает
        // подсказкой, и человек понимает, что от него хотят. Это слабее
        // настоящей подписи (подсказка исчезает при вводе), но блокером
        // не является, а ложный блокер в отчёте дороже пропущенной мелочи.
        let placeholder = utterance.placeholder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard placeholder.isEmpty else { return nil }

        // Значение — тоже не блокер, и по той же причине, что подсказка:
        // человек что-то слышит.
        //
        // Правка по факту, найденному на чужом коде. Eureka и Charts:
        // слайдер без подписи произносится как «50 %, slider», поле — как
        // «2 015,00 RUB, textField». Правило называло это «элементом без
        // подписи», а рядом в доказательстве печатало реплику, из которой
        // видно, что элемент прекрасно говорит. Владелец приложения читает
        // такое как ошибку инструмента, и он прав.
        //
        // Дефект здесь есть, но ДРУГОЙ: назначение неизвестно при известном
        // значении. Им занимается ValueWithoutNameRule, и severity там ниже.
        let value = utterance.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let visible = utterance.visibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.isEmpty, visible.isEmpty else { return nil }

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
