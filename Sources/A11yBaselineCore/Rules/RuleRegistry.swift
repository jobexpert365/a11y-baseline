import Foundation

/// Набор правил, применяемых к экрану.
public struct RuleRegistry: Sendable {

    public private(set) var rules: [any Rule]

    public init(rules: [any Rule]) {
        self.rules = rules
    }

    /// Правила, включённые по умолчанию.
    ///
    /// Здесь только те, у которых доля ложных срабатываний на реальных
    /// приложениях достаточно мала, чтобы отчёт не приходилось чистить руками.
    /// Всё, что шумит, живёт вне этого списка и включается явно.
    public static var standard: RuleRegistry {
        RuleRegistry(rules: [
            EmptyUtteranceRule(),
            GenericLabelRule(),
            FilenameLabelRule(),
            DuplicateLabelRule(),
            LabelInNameRule(),
            TargetSizeRule(),
            ReadingOrderRule(),
        ])
    }

    /// Прогоняет все правила по экрану.
    ///
    /// Находки сортируются по серьёзности, а внутри неё — по порядку обхода:
    /// человек читает отчёт сверху вниз и должен встретить сначала то, что
    /// ломает задачу целиком.
    public func run(on screen: ScreenSnapshot, locale: String) -> [Finding] {
        let context = RuleContext(screen: screen, locale: locale)
        var findings: [Finding] = []

        for rule in rules {
            for utterance in screen.utterances {
                if let finding = rule.evaluate(utterance, in: context) {
                    findings.append(finding)
                }
            }
        }

        return findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return (lhs.utteranceIndex ?? 0) < (rhs.utteranceIndex ?? 0)
        }
    }

    /// Прогоняет правила по всей базовой линии, отбрасывая принятые исключения.
    public func run(on baseline: Baseline) -> [Finding] {
        baseline.screens
            .flatMap { run(on: $0, locale: baseline.locale) }
            .filter { !baseline.acceptedFindingKeys.contains($0.key) }
    }
}
