import Foundation

/// Порядок обхода расходится с визуальным порядком.
///
/// Человек, который видит экран, и человек, который его слушает, должны
/// получать информацию в одной последовательности. Расхождение возникает,
/// когда элементы добавлены в иерархию не в том порядке, в каком они
/// расположены, — типично после рефакторинга вёрстки.
///
/// Правило намеренно консервативное: оно срабатывает только на разрыве через
/// несколько позиций, потому что мелкие перестановки внутри строки — норма
/// и сообщать о них значит засорять отчёт.
public struct ReadingOrderRule: Rule {

    public static let id = "reading-order"
    public static let standard = Standards.meaningfulSequence

    /// На сколько позиций элемент должен «уехать», чтобы это считалось находкой.
    private static let jumpThreshold = 3

    /// Насколько элементы должны различаться по вертикали, чтобы считать их
    /// принадлежащими разным строкам, а не одной.
    private static let rowTolerance: Double = 24

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard let frame = utterance.frame else { return nil }

        // Визуальный порядок: сверху вниз, внутри строки — слева направо.
        // Для языков с письмом справа налево порядок внутри строки обратный,
        // но вертикальная составляющая та же, поэтому правило работает и там.
        let isRTL = context.locale.hasPrefix("ar") || context.locale.hasPrefix("he") || context.locale.hasPrefix("fa")
        let visual = context.screen.utterances
            .compactMap { u -> (Utterance, Rect)? in u.frame.map { (u, $0) } }
            .sorted { lhs, rhs in
                if abs(lhs.1.y - rhs.1.y) > Self.rowTolerance { return lhs.1.y < rhs.1.y }
                return isRTL ? lhs.1.x > rhs.1.x : lhs.1.x < rhs.1.x
            }
            .map(\.0)

        guard let visualPosition = visual.firstIndex(where: { $0.index == utterance.index }) else { return nil }

        // Сравниваем позицию в обходе с позицией в визуальном порядке.
        // Обе позиции считаются среди элементов, у которых есть frame, —
        // иначе элементы без геометрии сдвигали бы отсчёт.
        let traversalPosition = context.screen.utterances
            .filter { $0.frame != nil }
            .firstIndex(where: { $0.index == utterance.index }) ?? 0

        let drift = traversalPosition - visualPosition
        guard abs(drift) >= Self.jumpThreshold else { return nil }

        // Сообщаем один раз на экран — о самом сильном расхождении.
        // Иначе одна перепутанная группа даёт десяток находок.
        let strongestDrift = context.screen.utterances
            .filter { $0.frame != nil }
            .enumerated()
            .compactMap { position, u -> Int? in
                guard let vp = visual.firstIndex(where: { $0.index == u.index }) else { return nil }
                return abs(position - vp)
            }
            .max() ?? 0
        guard abs(drift) == strongestDrift else { return nil }

        let direction = drift > 0 ? "позже" : "раньше"
        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .moderate,
            screen: context.screen.screen,
            summary: "Порядок чтения расходится с расположением на экране",
            evidence: "Элемент «\(utterance.label ?? utterance.spoken)» читается на \(abs(drift)) позиции \(direction), чем расположен визуально. Слушающий получает содержимое в другой последовательности, чем видящий.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "// порядок задан иерархией представлений",
                after: "container\n    .accessibilityElement(children: .contain)\n    .accessibilitySortPriority(...)",
                note: "На UIKit тот же результат даёт accessibilityElements у контейнера: порядок задаётся явно, а не наследуется от вёрстки."
            )
        )
    }
}
