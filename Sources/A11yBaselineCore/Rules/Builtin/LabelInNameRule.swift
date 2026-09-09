import Foundation

/// Видимая надпись не входит в программное имя.
///
/// Ломает Voice Control: человек говорит «Нажать Отправить», потому что видит
/// на кнопке слово «Отправить», а система ищет элемент с таким именем и не
/// находит, потому что в подписи написано что-то другое.
///
/// Это то место, где расходятся аудит «для VoiceOver» и аудит «для управления
/// голосом»: элемент может быть безупречно озвучен и при этом недоступен для
/// голосовой команды.
public struct LabelInNameRule: Rule {

    public static let id = "label-in-name"
    public static let standard = Standards.labelInName

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance),
              let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              let visible = utterance.visibleText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty, !visible.isEmpty else { return nil }

        // Сравниваем по нормализованным словам: регистр и знаки препинания
        // системе безразличны, порядок слов — нет.
        let normalizedLabel = normalize(label)
        let normalizedVisible = normalize(visible)
        guard !normalizedVisible.isEmpty, !normalizedLabel.contains(normalizedVisible) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            summary: "Видимая надпись «\(visible)» не входит в подпись «\(label)»",
            evidence: "Человек скажет «Нажать \(visible)», а система такого элемента не найдёт: программно он называется «\(label)».",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: ".accessibilityLabel(\"\(label)\")",
                after: ".accessibilityLabel(\"\(visible)\")",
                note: "Если подпись должна быть длиннее видимой надписи — видимый текст обязан быть в её начале: «\(visible), \(label)»."
            )
        )
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
