import Foundation

/// Подпись, которую система вывела из имени символа, а не написал человек.
///
/// Найдено живым прогоном, а не придумано: кнопка `Image(systemName:
/// "paperplane")` без явной подписи не остаётся немой — SwiftUI подставляет
/// имя символа, и в русском приложении VoiceOver произносит «Send».
/// Формально подпись есть, поэтому ни встроенный аудит Apple, ни правило
/// пустой подписи такой элемент не ловят. Человек при этом слышит английское
/// техническое слово вместо назначения кнопки.
///
/// Правило намеренно узкое, потому что ложная находка здесь дороже пропуска:
/// сработает только на элементе без видимого текста, с подписью из одного
/// латинского слова, и только если язык приложения не английский.
/// Бренды и аббревиатуры («OK», «PDF») отсекаются требованием длины и тем,
/// что у кнопки с брендом обычно есть видимый текст.
public struct SymbolDerivedLabelRule: Rule {

    public static let id = "symbol-derived-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        // Для англоязычного приложения английская подпись — норма.
        guard !context.locale.hasPrefix("en") else { return nil }
        guard context.isInteractive(utterance) else { return nil }

        // Есть видимый текст — значит подпись писал человек под этот текст.
        guard utterance.visibleText == nil else { return nil }

        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              label.count >= 4,
              !label.contains(" ") else { return nil }

        // Только латиница, только буквы: цифры и кириллица исключают случай.
        let isPureLatinWord = label.allSatisfy { $0.isLetter && $0.isASCII }
        guard isPureLatinWord else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            summary: "Подпись «\(label)» похожа на имя символа, а не на текст для человека",
            evidence: "VoiceOver произносит «\(utterance.spoken)» — английское слово в приложении на языке «\(context.locale)». Скорее всего, подпись не задана явно и система вывела её из имени SF Symbol.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Button(action: send) {\n    Image(systemName: \"paperplane\")\n}",
                after: "Button(action: send) {\n    Image(systemName: \"paperplane\")\n}\n.accessibilityLabel(\"Отправить\")",
                note: "Подпись описывает действие на языке пользователя, а не имя символа из кода."
            )
        )
    }
}
