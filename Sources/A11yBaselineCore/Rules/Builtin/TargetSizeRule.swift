import Foundation

/// Цель нажатия меньше минимального размера.
///
/// Порог 44 пункта — требование Apple Human Interface Guidelines, оно же
/// совпадает с уровнем AAA WCAG. Стандарт EN 301 549 требует 24 пункта
/// (уровень AA), поэтому правило различает две границы: ниже 24 — нарушение
/// стандарта, между 24 и 44 — отступление от рекомендации платформы.
public struct TargetSizeRule: Rule {

    public static let id = "target-size"
    public static let standard = Standards.targetSize

    /// Минимум по стандарту, уровень AA.
    private static let standardMinimum: Double = 24

    /// Минимум по рекомендациям Apple.
    private static let platformMinimum: Double = 44

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance),
              let frame = utterance.frame,
              frame.minSide > 0,
              frame.minSide < Self.platformMinimum else { return nil }

        let violatesStandard = frame.minSide < Self.standardMinimum
        let side = Int(frame.minSide.rounded())

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: violatesStandard ? .serious : .minor,
            screen: context.screen.screen,
            summary: violatesStandard
                ? "Цель нажатия \(side) пт — меньше требуемых 24 пт"
                : "Цель нажатия \(side) пт — меньше рекомендованных Apple 44 пт",
            evidence: "Элемент «\(utterance.label ?? utterance.spoken)» имеет размер \(Int(frame.width.rounded()))×\(Int(frame.height.rounded())) пт. В попадание промахиваются при треморе и при управлении переключателями.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Image(systemName: \"xmark\")\n    .onTapGesture { close() }",
                after: "Button(action: close) {\n    Image(systemName: \"xmark\")\n        .frame(width: 44, height: 44)\n}",
                note: "Область нажатия расширяется без изменения вида картинки: увеличивается frame, а не сам символ."
            )
        )
    }
}
