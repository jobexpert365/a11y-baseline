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
            SymbolNameLabelRule(),
            UntranslatedLabelRule(),
            FilenameLabelRule(),
            DuplicateLabelRule(),
            LabelInNameRule(),
        ])
    }

    /// Набор правил, соответствующий тому, чем снята базовая линия.
    ///
    /// Не всякое правило имеет право работать на всяких данных, и это
    /// измерено, а не выведено. `ReadingOrderRule` судит о ПОРЯДКЕ обхода,
    /// а порядок в дереве XCUITest — это порядок иерархии представлений,
    /// а не порядок, в котором идёт VoiceOver. Прогон по «Настройкам» iOS,
    /// приложению Apple с образцовой доступностью, дал на приближении две
    /// находки порядка чтения — то есть правило судило о том, чего в данных
    /// нет. На настоящей речи VoiceOver порядок известен точно, и там правило
    /// осмысленно.
    ///
    /// Принцип общий: правило включается только там, где источник даёт то,
    /// о чём правило судит. Иначе инструмент уверенно сообщает о дефектах,
    /// которых нет, и это худший вид ошибки — он выглядит как работа.
    public static func standard(for fidelity: CaptureFidelity) -> RuleRegistry {
        switch fidelity {
        case .voiceOverService:
            RuleRegistry(rules: standard.rules + [ReadingOrderRule()])
        case .accessibilityTree, .fixture:
            standard
        }
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

        return Self.collapse(findings).sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.occurrences != rhs.occurrences { return lhs.occurrences > rhs.occurrences }
            return (lhs.utteranceIndex ?? 0) < (rhs.utteranceIndex ?? 0)
        }
    }

    /// Схлопывает повторы одного и того же дефекта в одну находку со счётчиком.
    ///
    /// Группировка идёт по правилу и по ТЕКСТУ находки, а не по элементу:
    /// двадцать картинок с подписью «dough/brown-thumb» — это один дефект,
    /// встреченный двадцать раз, и чинится он одной правкой. Ключ первой
    /// находки сохраняется, чтобы принятые исключения продолжали работать.
    static func collapse(_ findings: [Finding]) -> [Finding] {
        var order: [String] = []
        var grouped: [String: Finding] = [:]

        for finding in findings {
            let groupKey = "\(finding.ruleID)|\(finding.screen)|\(finding.summary)"
            if var existing = grouped[groupKey] {
                existing.occurrences += 1
                grouped[groupKey] = existing
            } else {
                grouped[groupKey] = finding
                order.append(groupKey)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    /// Прогоняет правила по всей базовой линии, отбрасывая принятые исключения.
    public func run(on baseline: Baseline) -> [Finding] {
        baseline.screens
            .flatMap { run(on: $0, locale: baseline.locale) }
            .filter { !baseline.acceptedFindingKeys.contains($0.key) }
    }

    /// Прогоняет набор, подобранный под точность съёма этой базовой линии.
    /// Это способ по умолчанию: он не даёт правилу судить о том, чего
    /// в данных нет.
    public static func runMatching(_ baseline: Baseline) -> [Finding] {
        standard(for: baseline.fidelity).run(on: baseline)
    }
}
