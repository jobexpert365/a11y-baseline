import Foundation

/// Роль элемента продублирована в его подписи.
///
/// VoiceOver объявляет роль сам: у кнопки с подписью «Отправить» он произносит
/// «Отправить, кнопка». Если разработчик написал подпись «Кнопка отправить»,
/// человек услышит «Кнопка отправить, кнопка» — роль дважды, и вторая часть
/// звучит как оговорка.
///
/// Дефект распространённый и происходит из добрых намерений: подпись пишут
/// «понятнее», не зная, что система добавит роль сама. Встроенный аудит Apple
/// его не ловит — с точки зрения проверки «есть ли описание» всё в порядке.
///
/// Правило срабатывает ТОЛЬКО когда слово роли стоит ПОСЛЕДНИМ, и это
/// сужение появилось после провалившегося теста, а не из осторожности.
///
/// Первая версия ловила роль и в начале подписи — и обвинила «Кнопка вызова
/// экстренных служб». Это законное название: «кнопка» там главное слово
/// именной группы, а не дубль роли. Отличить его от «Кнопка отправить» можно
/// только грамматикой (родительный падеж против инфинитива), а грамматику
/// машина здесь не разберёт.
///
/// Поэтому ловим только однозначный случай: «Отправить кнопка», «Send button».
/// Роль в начале правило пропустит — осознанный размен полноты на молчание,
/// потому что ложное обвинение дороже пропуска.
public struct RoleInLabelRule: Rule {

    public static let id = "role-in-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    /// Слова роли по-русски и по-английски, сопоставленные признакам.
    /// Список закрытый: сюда входят только те роли, которые VoiceOver
    /// действительно произносит вслух.
    private static let roleWords: [String: Set<String>] = [
        "button": ["кнопка", "кнопку", "button"],
        "link": ["ссылка", "ссылку", "link"],
        "image": ["изображение", "картинка", "image", "picture"],
        "textField": ["поле", "field"],
        "toggle": ["переключатель", "toggle", "switch"],
        "slider": ["ползунок", "slider"],
    ]

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }

        let words = label.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Подпись из одного слова — это случай другого правила: там роль
        // стоит ВМЕСТО назначения, а не рядом с ним.
        guard words.count >= 2 else { return nil }

        // Верхняя граница длины, и она появилась после первого же
        // срабатывания правила на живом приложении.
        //
        // В примере PopupView есть подпись «Top float with a picture and one
        // button». Она заканчивается словом «button», и правило объявило это
        // дублированием роли. Но «one button» здесь — часть ОПИСАНИЯ того,
        // как выглядит попап, а не название элемента.
        //
        // Дублирование роли — это всегда короткая подпись: «Отправить кнопка»,
        // «Send button». Длинная фраза, случайно оканчивающаяся на слово роли,
        // дублированием не является. Три слова — граница, за которой подпись
        // перестаёт быть названием и становится описанием.
        guard words.count <= 3 else { return nil }

        for trait in utterance.traits {
            guard let roleVariants = Self.roleWords[trait] else { continue }
            guard let last = words.last, roleVariants.contains(last) else { continue }
            let duplicated = last

            return Finding(
                key: makeKey(screen: context.screen.screen, utterance: utterance),
                ruleID: Self.id,
                source: .ruleEngine,
                severity: .moderate,
                screen: context.screen.screen,
                summary: "Роль продублирована в подписи: «\(label)»",
                evidence: "VoiceOver произносит «\(utterance.spoken)» — слово «\(duplicated)» звучит дважды, потому что систему роль объявляет сама.",
                standard: Self.standard,
                utteranceIndex: utterance.index,
                fix: Finding.Fix(
                    before: ".accessibilityLabel(\"\(label)\")",
                    after: ".accessibilityLabel(\"\(Self.stripRole(from: label, word: duplicated))\")",
                    note: "Роль добавляет система. В подписи остаётся только назначение."
                )
            )
        }
        return nil
    }

    /// Убирает слово роли с края подписи, сохраняя остальное как есть.
    static func stripRole(from label: String, word: String) -> String {
        var parts = label.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.first?.lowercased().trimmingCharacters(in: .punctuationCharacters) == word {
            parts.removeFirst()
        } else if parts.last?.lowercased().trimmingCharacters(in: .punctuationCharacters) == word {
            parts.removeLast()
        }
        guard let first = parts.first else { return label }
        // Первое слово с заглавной: «кнопка Отправить» → «Отправить».
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " ")
    }
}
