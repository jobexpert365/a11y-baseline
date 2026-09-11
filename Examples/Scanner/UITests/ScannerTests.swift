import XCTest
import A11yBaselineCore
import A11yBaselineXCUI

/// Сканер чужих приложений.
///
/// Главное решение всего индекса живёт здесь, в одной строке:
/// `XCUIApplication(bundleIdentifier:)`. XCUITest умеет поднимать ЛЮБОЕ
/// установленное на симуляторе приложение, а не только то, вместе с которым
/// собран тест. Значит проверка чужого приложения не требует ни его исходников,
/// ни правки его проекта, ни отдельного тест-таргета внутри него.
///
/// Без этого индекс не построить: править чужой проект ради одной страницы
/// никто не станет, и на десятом приложении затея умрёт. С этим — сканирование
/// становится конвейером: поставил, запустил, снял базовую линию.
///
/// Параметры приходят из окружения, потому что тест запускается пачкой
/// из скрипта, а не руками из Xcode:
///   A11Y_BUNDLE_ID   — что сканировать (обязательно)
///   A11Y_APP_NAME    — как называть в отчёте
///   A11Y_LOCALE      — язык интерфейса приложения
///   A11Y_MAX_SCREENS — сколько экранов обойти
/// Ошибки обхода. Отдельный тип, а не XCTSkip: XCTSkip прерывает весь тест
/// и выбрасывает уже снятые экраны, а недостижимый раздел — это меньшее
/// покрытие, а не провал прогона.
enum ScanError: Error {
    case tabUnavailable(String)
    case nowhereToGo
}

final class ScannerTests: XCTestCase {

    @MainActor
    func testScanInstalledApp() throws {
        let env = ProcessInfo.processInfo.environment
        guard let bundleID = env["A11Y_BUNDLE_ID"], !bundleID.isEmpty else {
            throw XCTSkip("A11Y_BUNDLE_ID не задан — сканировать нечего")
        }

        let appName = env["A11Y_APP_NAME"] ?? bundleID
        let locale = env["A11Y_LOCALE"] ?? "ru"
        let maxScreens = Int(env["A11Y_MAX_SCREENS"] ?? "1") ?? 1

        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение \(bundleID) не запустилось")

        // Обход: первый экран всегда, дальше — вглубь по первому доступному
        // элементу навигации. Это намеренно примитивная стратегия. Умный обход
        // чужого приложения требует знания его структуры, которого у нас нет,
        // а неверный обход хуже мелкого: он уводит в случайные состояния
        // и делает базовую линию невоспроизводимой между прогонами.
        var steps: [WalkPlan.Step] = [
            .init(screen: "Стартовый экран") { _ in }
        ]
        for depth in 1..<max(1, maxScreens) {
            steps.append(.init(screen: "Экран \(depth + 1)") { app in
                let candidates = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "elementType IN {%d, %d}",
                                          XCUIElement.ElementType.cell.rawValue,
                                          XCUIElement.ElementType.button.rawValue))
                let target = candidates.allElementsBoundByIndex
                    .first { $0.exists && $0.isHittable && !$0.label.isEmpty }
                guard let target else { throw XCTSkip("дальше идти некуда") }
                target.tap()
                _ = app.wait(for: .runningForeground, timeout: 3)
            })
        }

        let recorder = BaselineRecorder(app: app, source: AccessibilityTreeSource(app: app))
        var baseline = try recorder.record(plan: WalkPlan(steps: steps), appVersion: "—", locale: locale)
        baseline.app = appName

        let findings = RuleRegistry.runMatching(baseline)

        // Результат кладём в общий каталог симулятора, откуда его забирает
        // скрипт конвейера: писать в песочницу приложения-носителя нельзя,
        // её путь меняется от прогона к прогону.
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = outDir.appendingPathComponent("scan-\(bundleID).json")
        try BaselineStore().encode(baseline).write(to: out)

        print("A11Y_SCAN_OUTPUT=\(out.path)")
        print("A11Y_SCAN_APP=\(appName)")
        print("A11Y_SCAN_ELEMENTS=\(baseline.screens.reduce(0) { $0 + $1.utterances.count })")
        print("A11Y_SCAN_FINDINGS=\(findings.count)")
        for finding in findings {
            print("A11Y_SCAN_FINDING=\(finding.severity.rawValue)|\(finding.ruleID)|\(finding.summary)")
        }
    }
}
