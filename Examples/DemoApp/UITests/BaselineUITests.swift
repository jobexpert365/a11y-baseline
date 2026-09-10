import XCTest
import A11yBaselineCore
import A11yBaselineXCUI

/// Прогон пакета на живом приложении в симуляторе.
///
/// Тест намеренно не утверждает «находок должно быть ровно N»: цель прогона —
/// не зафиксировать число, а получить настоящий отчёт и посмотреть на него
/// глазами. Проверяются два свойства, которые обязаны выполняться всегда:
/// правила находят заложенные дефекты и НЕ трогают контрольный элемент.
final class BaselineUITests: XCTestCase {

    @MainActor
    func testCaptureBaselineAndReport() throws {
        let app = XCUIApplication()
        app.launch()

        let plan = WalkPlan(steps: [
            .init(screen: "Каталог") { _ in }
        ])

        let recorder = BaselineRecorder(app: app, source: AccessibilityTreeSource(app: app))
        let baseline = try recorder.record(plan: plan, appVersion: "1.0")

        // Диагностика: что именно собрано с экрана.
        for u in baseline.screens[0].utterances {
            let f = u.frame.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
            print("A11Y_ELEM=\(u.index)|traits=\(u.traits.joined(separator: "+"))|\(f)|label=\(u.label ?? "nil")|id=\(u.identifier ?? "-")")
        }

        let findings = RuleRegistry.runMatching(baseline)
        let report = MarkdownReport().render(baseline: baseline, findings: findings)

        // Отчёт и базовая линия кладутся в результат прогона, чтобы их можно
        // было достать из xcresult и посмотреть, а не гадать по логам.
        let reportAttachment = XCTAttachment(string: report)
        reportAttachment.name = "a11y-report.md"
        reportAttachment.lifetime = .keepAlways
        add(reportAttachment)

        let baselineAttachment = XCTAttachment(data: try BaselineStore().encode(baseline))
        baselineAttachment.name = "baseline.json"
        baselineAttachment.lifetime = .keepAlways
        add(baselineAttachment)

        // Дублируем в файл: так проще читать из скрипта и из CI.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = tmp.appendingPathComponent("a11y-report.md")
        try report.write(to: out, atomically: true, encoding: .utf8)
        let baselineOut = tmp.appendingPathComponent("baseline.json")
        try BaselineStore().encode(baseline).write(to: baselineOut)
        print("A11Y_REPORT_PATH=\(out.path)")
        print("A11Y_BASELINE_PATH=\(baselineOut.path)")
        print("A11Y_FINDINGS_COUNT=\(findings.count)")
        for finding in findings {
            print("A11Y_FINDING=\(finding.severity.rawValue)|\(finding.ruleID)|\(finding.summary)")
        }

        let rules = Set(findings.map(\.ruleID))
        // Ожидание исправлено по результату живого прогона. Кнопка без явной
        // подписи не остаётся немой: SwiftUI подставляет имя SF-символа, и
        // VoiceOver произносит «Send» в русском приложении. Настоящий дефект
        // здесь — не отсутствие подписи, а подпись из кода вместо текста для
        // человека, и ловит его symbol-derived-label.
        XCTAssertTrue(rules.contains("symbol-derived-label"), "не найдена подпись, выведенная из имени символа")
        XCTAssertTrue(rules.contains("generic-label"), "не найдена подпись-заглушка")
        XCTAssertTrue(rules.contains("filename-label"), "не найдено имя ресурса в подписи")
        XCTAssertTrue(rules.contains("duplicate-label"), "не найдены одинаково звучащие элементы")

        // Главная проверка: контрольный элемент не должен попасть в отчёт.
        let falsePositives = findings.filter { $0.evidence.contains("Сохранить черновик") }
        XCTAssertTrue(falsePositives.isEmpty, "движок шумит на корректном элементе: \(falsePositives.map(\.summary))")
    }
}
