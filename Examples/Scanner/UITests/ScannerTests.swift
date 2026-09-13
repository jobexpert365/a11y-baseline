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

        // Сначала гасим, потом запускаем. Без этого приложение, оставшееся
        // с прошлого прогона, поднимается НА ТОМ ЖЕ ЭКРАНЕ, где его бросили,
        // и сценарий строится не по корню, а по случайному месту.
        //
        // Поймано сравнением повторных прогонов «Контактов»: один и тот же
        // код давал то 6 экранов и 85 элементов, то 2 и 30. Во втором случае
        // приложение открывалось сразу на карточке контакта, где список
        // из двенадцати строк превращался в одну.
        //
        // Для индекса это принципиально: на каждой странице написано, что
        // результат воспроизводим. Пока обход зависел от того, чем кончился
        // предыдущий прогон, это было неправдой.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "приложение \(bundleID) не запустилось")

        // Профиль загрузки под флагом. Оставлено в боевом коде: именно эта
        // трассировка показала, что у Pulse длинное ложное плато в начале
        // (2,2,2,2,2,2,4,4,4,6,6,6,6,7,7,7,9,...), и объяснила, почему правило
        // «два одинаковых замера подряд» строило сценарий на двух строках
        // вместо девяти. Включается TEST_RUNNER_A11Y_TRACE_LOAD=1.
        if ProcessInfo.processInfo.environment["A11Y_TRACE_LOAD"] != nil {
            var series: [Int] = []
            for _ in 0..<30 {
                series.append(app.cells.count)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
            print("A11Y_LOAD_TRACE=\(series.map(String.init).joined(separator: ","))")
        }
        waitForContent(app)
        goToRoot(app)
        probe(app)
        let steps = plan(for: app, budget: maxScreens)
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

    /// Ждёт, пока приложение дорисует содержимое, и только потом строит сценарий.
    ///
    /// Без этого обход был НЕВОСПРОИЗВОДИМ. Замер профиля загрузки показал,
    /// почему простого «счётчик не изменился» мало. Pulse набирает строки
    /// семь секунд, и в начале у него ДЛИННОЕ ЛОЖНОЕ ПЛАТО:
    ///
    ///     2,2,2,2,2,2,4,4,4,6,6,6,6,7,7,7,9,9,9,9,9,...
    ///
    /// Первые шесть замеров подряд дают двойку — прежнее правило «два
    /// одинаковых замера подряд» срабатывало здесь и строило сценарий
    /// на двух строках вместо девяти. Отсюда и брались 3 экрана против 4
    /// между прогонами.
    ///
    /// Поэтому условий ДВА, и нужны оба: счётчик держится `stableFor` секунд
    /// И с запуска прошло не меньше `minimumElapsed`. Нижняя граница
    /// проламывает ложные плато, верхняя — не даёт ждать вечно приложение,
    /// которое грузит бесконечно.
    @MainActor
    private func waitForContent(
        _ app: XCUIApplication,
        minimumElapsed: TimeInterval = 5,
        stableFor: TimeInterval = 3,
        timeout: TimeInterval = 20
    ) {
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        var previous = -1
        var unchangedSince = started

        while Date() < deadline {
            let count = app.cells.count
            if count != previous {
                previous = count
                unchangedSince = Date()
            }

            let held = Date().timeIntervalSince(unchangedSince)
            let elapsed = Date().timeIntervalSince(started)
            if held >= stableFor && elapsed >= minimumElapsed { return }

            // Пауза через RunLoop, а не sleep: главный поток остаётся живым,
            // иначе запросы XCUITest к приложению встают вместе с ним.
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    /// Уводит приложение в корень, откуда бы оно ни поднялось.
    ///
    /// Приложение восстанавливает тот экран, на котором его закрыли, и снять
    /// это `terminate()` не может — состояние лежит на диске. Наш же обход
    /// сам и оставляет приложение на карточке, в которую зашёл. Получалась
    /// петля: «Контакты» давали 6 экранов и 85 элементов, потом 2 и 30, потом
    /// снова 6 — ровно через раз, потому что каждый прогон начинался там,
    /// где кончился предыдущий.
    ///
    /// Кнопку возврата ищем по СИСТЕМНОМУ признаку, а не по первой попавшейся
    /// кнопке панели: первой может оказаться «Изменить» или «Отменить»,
    /// и нажимать их вслепую — значит менять чужие данные.
    @MainActor
    private func goToRoot(_ app: XCUIApplication, maxDepth: Int = 6) {
        for _ in 0..<maxDepth {
            let back = app.navigationBars.buttons.matching(
                NSPredicate(format: "identifier == %@ OR identifier == %@", "BackButton", "UINavigationBarBackButton")
            ).firstMatch

            guard back.exists, back.isHittable else { return }
            back.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    /// Сводка дерева на момент построения сценария.
    ///
    /// Оставлено в боевом коде сознательно: каждая пойманная в этом проекте
    /// невоспроизводимость ловилась именно сравнением этой строки между
    /// прогонами, а не чтением кода. Скрипт сборки индекса её отфильтровывает,
    /// так что в отчёт она не попадает.
    @MainActor
    private func probe(_ app: XCUIApplication) {
        print("A11Y_PROBE=панелей:\(app.navigationBars.count) кнопок_панели:\(app.navigationBars.buttons.allElementsBoundByIndex.map(\.identifier).joined(separator: ",")) ячеек:\(app.cells.count) таблиц:\(app.tables.count) строк_таблиц:\(app.tables.cells.count) коллекций:\(app.collectionViews.count) ячеек_коллекций:\(app.collectionViews.cells.count) кнопок:\(app.buttons.count) вкладок:\(app.tabBars.buttons.count)")
    }

    // MARK: - Построение сценария обхода

    /// Строит сценарий обхода для незнакомого приложения.
    ///
    /// Две стратегии, и выбор между ними делает само приложение. Обе
    /// самодостаточны: каждый шаг сам приводит приложение в нужное место,
    /// поэтому провал одного шага не портит остальные.
    @MainActor
    private func plan(for app: XCUIApplication, budget: Int) -> [WalkPlan.Step] {
        let tabs = app.tabBars.buttons.allElementsBoundByIndex
            .filter { $0.exists && !$0.label.isEmpty }
            .map(\.label)

        return tabs.isEmpty
            ? planByList(app: app, budget: budget)
            : planByTabs(app: app, tabs: tabs, budget: budget)
    }

    /// СТРАТЕГИЯ 1 — ВКЛАДКИ, И ПО ОДНОМУ УРОВНЮ ВГЛУБЬ В КАЖДОЙ.
    ///
    /// Раньше обход по вкладкам ходил только по их корням, и это измеримо
    /// дорого стоило: на Food Truck переход с прежнего обхода вглубь на обход
    /// по вкладкам уронил число находок с 63 до 20. Находки никуда не делись —
    /// просто часть из них живёт глубже первого экрана вкладки. Обратный
    /// пример — «Фото»: там обход вглубь давал 0, а по вкладкам сразу 10.
    ///
    /// Вывод из этих двух чисел: ни ширина, ни глубина по отдельности
    /// не покрывают приложение. Сначала берём все вкладки, потом спускаемся
    /// на уровень внутри каждой.
    ///
    /// Шаги вглубь строятся ВСЛЕПУЮ, без предварительной разведки. Разведка
    /// (проход по вкладкам ради имён разделов) была написана и выброшена:
    /// она оставляла «Фото» на вкладке «Поиск» с поднятой клавиатурой,
    /// вкладки становились недоступны, и обход снимал ноль экранов вместо
    /// трёх. Шаг, которому некуда спускаться, просто отваливается сам
    /// и стоит пары секунд — это дешевле порчи состояния.
    @MainActor
    private func planByTabs(app: XCUIApplication, tabs: [String], budget: Int) -> [WalkPlan.Step] {
        // Стартовый экран снимается ВСЕГДА, даже когда есть вкладки.
        //
        // Первая версия его выбрасывала, считая дублем первой вкладки. Замер
        // показал обратное: в «Фото» стартовый экран — это 49 элементов,
        // а вкладка «Медиатека» после нажатия — 13, то есть разные экраны.
        // В «Здоровье» стартовый экран вообще единственный достижимый,
        // и без него приложение давало НОЛЬ экранов. Настоящий дубль отсеет
        // сам рекордер, он сравнивает содержимое.
        var steps: [WalkPlan.Step] = [.init(screen: "Стартовый экран", anchored: true) { _ in }]

        // Сначала вся ширина, потом глубина. Порядок именно такой: обход
        // по вкладкам надёжен и дёшев, а спуск вглубь зависит от содержимого
        // и чаще срывается. Если бюджет кончится, потерять лучше глубину.
        for label in tabs.prefix(max(0, budget - 1)) {
            steps.append(.init(screen: label, anchored: true) { app in
                let tab = app.tabBars.buttons[label]
                guard tab.exists, tab.isHittable else { throw ScanError.unreachable(label) }
                tab.tap()
                _ = app.wait(for: .runningForeground, timeout: 3)
            })
        }

        for label in tabs {
            guard steps.count < budget else { break }
            steps.append(.init(
                screen: "\(label) — раздел",
                anchored: true,
                resolveName: { Self.currentScreenTitle($0) }
            ) { app in
                // Возврат к известному месту перед спуском. Нажатие вкладки
                // с любого экрана возвращает её в корень — это и есть
                // причина, по которой шаг самодостаточен.
                let tab = app.tabBars.buttons[label]
                guard tab.exists, tab.isHittable else { throw ScanError.unreachable(label) }
                tab.tap()
                _ = app.wait(for: .runningForeground, timeout: 2)

                let cells = app.cells.allElementsBoundByIndex
                let hittable = cells.filter { $0.exists && $0.isHittable }
                print("A11Y_DEPTH_PROBE=\(label)|ячеек:\(cells.count)|доступных:\(hittable.count)|кнопок:\(app.buttons.count)|строк_таблиц:\(app.tables.cells.count)|ячеек_коллекций:\(app.collectionViews.cells.count)")
                guard let cell = hittable.first else { throw ScanError.unreachable(label) }
                cell.tap()
                _ = app.wait(for: .runningForeground, timeout: 3)
            })
        }

        return steps
    }

    /// Заголовок текущего экрана из панели навигации.
    ///
    /// Берём именно его, а не текст нажатой строки списка: заголовок — это
    /// то, как раздел называет сам себя, и владелец приложения узнает его
    /// в отчёте. Если панели нет, возвращаем nil, и остаётся имя из сценария.
    @MainActor
    private static func currentScreenTitle(_ app: XCUIApplication) -> String? {
        let bar = app.navigationBars.element(boundBy: 0)
        guard bar.exists else { return nil }
        if !bar.identifier.isEmpty { return bar.identifier }
        return bar.staticTexts.allElementsBoundByIndex.first?.label
    }

    /// СТРАТЕГИЯ 2 — СПИСОК С ВОЗВРАТОМ, если вкладок нет.
    ///
    /// Прежняя запасная стратегия жала «первый доступный элемент» и никуда
    /// не возвращалась: после первого нажатия мы оказывались внутри,
    /// а следующий шаг жал первое, что попалось уже там. На Charts это
    /// давало один экран из пяти — содержимое приложения оставалось
    /// непройденным, а сканер сообщал ноль находок по экрану меню.
    ///
    /// Ячейку опознаём по НОМЕРУ, а имя экрана берём из текста внутри неё:
    /// в Charts у ячеек таблицы пустая подпись, а текст лежит в дочернем
    /// элементе, поэтому отбор по непустой подписи давал пустой список.
    @MainActor
    private func planByList(app: XCUIApplication, budget: Int) -> [WalkPlan.Step] {
        var steps: [WalkPlan.Step] = [.init(screen: "Стартовый экран", anchored: true) { _ in }]

        let cellCount = min(app.cells.count, max(0, budget - 1))
        for index in 0..<max(0, cellCount) {
            let cell = app.cells.element(boundBy: index)
            let text = cell.staticTexts.allElementsBoundByIndex.first?.label ?? ""
            let name = text.isEmpty ? "Экран \(index + 2)" : text

            // Имя уточняем ПОСЛЕ перехода, по заголовку самого экрана.
            //
            // Имя из ячейки — это лишь предположение о том, куда она ведёт.
            // «Файлы» показали, чем это плохо: приложение чередует два
            // состояния запуска, и содержимое разделов уезжало под чужие
            // подписи — страница называла экран «Обзор», а показывала
            // «iCloud Drive». Расхождение в числах при этом было мелкое
            // (150 против 153), а подпись — прямо неверной.
            steps.append(.init(
                screen: name,
                anchored: true,
                resolveName: { Self.currentScreenTitle($0) }
            ) { app in
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

        return steps
    }
}
