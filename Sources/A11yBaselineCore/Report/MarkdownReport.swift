import Foundation

/// Отчёт в Markdown — то, что человек читает глазами.
///
/// Устройство отчёта повторяет устройство продажи: сначала то, что ломает
/// задачу, потом остальное, и отдельным разделом — находки встроенного аудита
/// платформы с явной пометкой, что они бесплатны. Последнее сделано осознанно:
/// покупатель должен видеть границу оплачиваемого, иначе он заподозрит, что
/// ему продают то, что и так раздаёт Apple.
public struct MarkdownReport: Sendable {

    public init() {}

    public func render(baseline: Baseline, findings: [Finding], diff: DiffResult? = nil) -> String {
        var out: [String] = []

        out.append("# Доступность: \(baseline.app) \(baseline.appVersion)")
        out.append("")
        out.append("iOS \(baseline.osVersion) · локаль \(baseline.locale) · съём: \(fidelityLabel(baseline.fidelity))")
        out.append("")

        let engineFindings = findings.filter { $0.source == .ruleEngine }
        let platformFindings = baseline.screens.flatMap(\.platformAuditFindings)

        out.append(summaryTable(engine: engineFindings, platform: platformFindings, diff: diff))
        out.append("")

        if let diff, !diff.regressions.isEmpty {
            out.append("## Регрессии относительно базовой линии")
            out.append("")
            out.append("Это то, что раньше работало, а теперь нет.")
            out.append("")
            for change in diff.regressions {
                out.append("- \(describe(change))")
            }
            out.append("")
        }

        for severity in [Severity.blocker, .serious, .moderate, .minor] {
            let group = engineFindings.filter { $0.severity == severity }
            guard !group.isEmpty else { continue }

            out.append("## \(severityTitle(severity)) — \(group.count)")
            out.append("")
            for finding in group {
                out.append(renderFinding(finding))
            }
        }

        if !platformFindings.isEmpty {
            out.append("## Что нашли бесплатные инструменты Apple — \(platformFindings.count)")
            out.append("")
            out.append("Этот раздел показан отдельно намеренно: находки ниже выдаёт встроенный")
            out.append("`performAccessibilityAudit`, он входит в Xcode и ничего не стоит.")
            out.append("")
            for finding in platformFindings {
                out.append("- **\(finding.screen)** — \(finding.summary)")
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }

    private func renderFinding(_ finding: Finding) -> String {
        var out: [String] = []
        out.append("### \(finding.summary)")
        out.append("")
        out.append("**Экран:** \(finding.screen)")
        if let standard = finding.standard {
            let wcag = standard.wcag22.map { " · WCAG \($0)" } ?? ""
            out.append("**Стандарт:** EN 301 549 п. \(standard.en301549)\(wcag) — \(standard.title)")
        }
        out.append("")
        out.append(finding.evidence)
        out.append("")

        if let fix = finding.fix {
            out.append("**Было:**")
            out.append("```swift")
            out.append(fix.before)
            out.append("```")
            out.append("")
            out.append("**Стало:**")
            out.append("```swift")
            out.append(fix.after)
            out.append("```")
            if let note = fix.note {
                out.append("")
                out.append("> \(note)")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    private func summaryTable(engine: [Finding], platform: [Finding], diff: DiffResult?) -> String {
        var rows: [String] = []
        rows.append("| | Количество |")
        rows.append("|---|---:|")
        for severity in [Severity.blocker, .serious, .moderate, .minor] {
            let count = engine.filter { $0.severity == severity }.count
            if count > 0 { rows.append("| \(severityTitle(severity)) | \(count) |") }
        }
        if let diff { rows.append("| Регрессии | \(diff.regressions.count) |") }
        if !platform.isEmpty { rows.append("| Встроенный аудит Apple | \(platform.count) |") }
        return rows.joined(separator: "\n")
    }

    private func severityTitle(_ severity: Severity) -> String {
        switch severity {
        case .blocker: "Задача невыполнима"
        case .serious: "Непонятно, что делает элемент"
        case .moderate: "Понятно с усилием"
        case .minor: "Мелочи"
        }
    }

    private func fidelityLabel(_ fidelity: CaptureFidelity) -> String {
        switch fidelity {
        case .voiceOverService: "настоящий VoiceOver"
        case .accessibilityTree: "дерево доступности (приближение)"
        case .fixture: "фикстура"
        }
    }

    private func describe(_ change: DiffResult.Change) -> String {
        let unreliable = change.matchedReliably ? "" : " _(сопоставление по позиции, возможна неточность)_"
        return switch change.kind {
        case .utteranceLost(let was):
            "**\(change.screen)** — элемент перестал озвучиваться. Было: «\(was)»\(unreliable)"
        case .elementDisappeared(let was):
            "**\(change.screen)** — элемент исчез из обхода. Было: «\(was)»\(unreliable)"
        case .newFinding(let finding):
            "**\(change.screen)** — новая находка: \(finding.summary)"
        case .utteranceChanged(let was, let now):
            "**\(change.screen)** — реплика изменилась: «\(was)» → «\(now)»\(unreliable)"
        case .elementAppeared(let now):
            "**\(change.screen)** — новый элемент: «\(now)»"
        case .reordered(let from, let to):
            "**\(change.screen)** — элемент переехал в обходе: \(from) → \(to)\(unreliable)"
        }
    }
}
