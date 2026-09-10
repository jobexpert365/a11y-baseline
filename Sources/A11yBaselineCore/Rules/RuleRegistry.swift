import Foundation

/// Набор правил, применяемых к экрану.
public struct RuleRegistry: Sendable {

    public private(set) var rules: [any Rule]

    public init(rules: [any Rule]) {
        self.rules = rules
    }

    /// Правила, включённые по умолчанию.
    ///
    /// Здесь только те, у которых доля ложных срабатываний на реальном
    /// приложении достаточно мала, чтобы отчёт не приходилось чистить руками.
    ///
    /// `TargetSizeRule` сюда НЕ входит, и это измеренное решение, а не вкус.
    /// Прогон на симуляторе показал: XCUITest отдаёт для SwiftUI-кнопки
    /// границы её содержимого, а не область нажатия — кнопка с явным
    /// `.frame(minHeight: 44)` приходит как 20 пт высотой. На таких данных
    /// правило давало находку почти на каждой кнопке, включая заведомо
    /// корректную. Размер цели измеряет встроенный `performAccessibilityAudit`,
    /// у него есть настоящая геометрия, и в том же прогоне он сообщил об этом
    /// сам. Дублировать чужую проверку хуже оригинала — ровно та ошибка,
    /// которой этот проект избегает.
    public static var standard: RuleRegistry {
        RuleRegistry(rules: [
            EmptyUtteranceRule(),
            GenericLabelRule(),
            SymbolDerivedLabelRule(),
            FilenameLabelRule(),
            DuplicateLabelRule(),
            LabelInNameRule(),
            ReadingOrderRule(),
        ])
    }

    /// Набор для источников, у которых геометрия соответствует области
    /// нажатия — например, для UIKit, где frame элемента доступности и есть
    /// цель. Включать только если вы это проверили на своём приложении.
    public static var withTrustedGeometry: RuleRegistry {
        RuleRegistry(rules: standard.rules + [TargetSizeRule()])
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
