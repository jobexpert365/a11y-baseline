import XCTest
import A11yBaselineCore
import A11yBaselineXCUI

/// Ошибки обхода. Отдельный тип, а не XCTSkip: XCTSkip прерывает весь тест
/// и выбрасывает уже снятые экраны, а недостижимый раздел — это меньшее
/// покрытие, а не провал прогона.
enum ScanError: Error {
    case unreachable(String)
}

/// Сканер чужих приложений.
///
/// Главное решение всего индекса живёт в одной строке:
/// `XCUIApplication(bundleIdentifier:)`. XCUITest умеет поднимать ЛЮБОЕ
/// установленное на симуляторе приложение, а не только то, вместе с которым
/// собран тест. Значит проверка чужого приложения не требует ни его
/// исходников, ни правки его проекта.
///
/// Параметры приходят из окружения, потому что тест запускается пачкой
/// из скрипта, а не руками из Xcode. Важно: xcodebuild передаёт в тест только
/// переменные с приставкой TEST_RUNNER_, она снимается автоматически.
///   A11Y_BUNDLE_ID   — что сканировать (обязательно)
///   A11Y_APP_NAME    — как называть в отчёте
///   A11Y_LOCALE      — язык интерфейса приложения
///   A11Y_MAX_SCREENS — сколько экранов обойти
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

        var steps: [WalkPlan.Step] = [.init(screen: "Стартовый экран") { _ in }]
        let budget = max(0, maxScreens - 1)

        // СТРАТЕГИЯ 1 — ВКЛАДКИ.
        //
        // Лучшая цель для автоматического обхода чужого приложения: вкладки
        // есть у большинства приложений, не зависят от содержимого (значит
        // обход воспроизводим между прогонами) и ведут в РАЗНЫЕ разделы,
        // а не вглубь одного. Имя экрана берём из подписи вкладки —
        // «Медиатека» в отчёте понятнее, чем «Экран 2».
        let tabLabels = app.tabBars.buttons.allElementsBoundByIndex
            .filter { $0.exists && !$0.label.isEmpty }
            .map(\.label)
            .prefix(budget)

        for label in tabLabels {
            steps.append(.init(screen: label) { app in
                let tab = app.tabBars.buttons[label]
                guard tab.exists, tab.isHittable else { throw ScanError.unreachable(label) }
                tab.tap()
                _ = app.wait(for: .runningForeground, timeout: 3)
            })
        }

        // СТРАТЕГИЯ 2 — СПИСОК С ВОЗВРАТОМ, если вкладок нет.
        //
        // Прежняя запасная стратегия жала «первый доступный элемент» и никуда
        // не возвращалась: после первого нажатия мы оказывались внутри,
        // а следующий шаг жал первое, что попалось уже там. На Charts это
        // давало один экран из пяти — содержимое приложения оставалось
        // непройденным, а сканер сообщал ноль находок по экрану меню.
        //
        // Ячейку опознаём по НОМЕРУ, а имя экрана берём из текста внутри неё:
        // в Charts у ячеек таблицы пустая подпись, а текст лежит в дочернем
        // элементе, поэтому отбор по непустой подписи давал пустой список.
        if tabLabels.isEmpty {
            let cellCount = min(app.cells.count, budget)
            for index in 0..<max(0, cellCount) {
                let cell = app.cells.element(boundBy: index)
                let text = cell.staticTexts.allElementsBoundByIndex.first?.label ?? ""
                let name = text.isEmpty ? "Экран \(index + 2)" : text

                steps.append(.init(screen: name) { app in
                    // Возврат в корень: первая кнопка панели навигации —
                    // это «назад». Если её нет, мы уже в корне.
                    let back = app.navigationBars.buttons.element(boundBy: 0)
                    if back.exists, back.isHittable {
                        back.tap()
                        _ = app.wait(for: .runningForeground, timeout: 2)
                    }
                    let target = app.cells.element(boundBy: index)
                    guard target.exists, target.isHittable else { throw ScanError.unreachable(name) }
                    target.tap()
                    _ = app.wait(for: .runningForeground, timeout: 3)
                })
            }
        }

        print("A11Y_WALK_PLAN=\(steps.map(\.screen).joined(separator: " | "))")

        let recorder = BaselineRecorder(app: app, source: AccessibilityTreeSource(app: app))
        var baseline = try recorder.record(plan: WalkPlan(steps: steps), appVersion: "—", locale: locale)
        baseline.app = appName

        let findings = RuleRegistry.runMatching(baseline)

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = tmp.appendingPathComponent("scan-\(bundleID).json")
        try BaselineStore().encode(baseline).write(to: out)

        print("A11Y_SCAN_OUTPUT=\(out.path)")
        print("A11Y_SCAN_APP=\(appName)")
        print("A11Y_SCAN_SCREENS=\(baseline.screens.count)")
        print("A11Y_SCAN_ELEMENTS=\(baseline.screens.reduce(0) { $0 + $1.utterances.count })")
        print("A11Y_SCAN_FINDINGS=\(findings.count)")
        for finding in findings {
            print("A11Y_SCAN_FINDING=\(finding.severity.rawValue)|\(finding.ruleID)|\(finding.summary)")
        }
    }
}
