#if canImport(XCTest) && canImport(XCUIAutomation)
import Foundation
import XCTest
import A11yBaselineCore

/// Сценарий обхода: набор экранов и способ до каждого добраться.
///
/// Навигация задаётся замыканием, а не декларацией, сознательно. Любая попытка
/// описать переходы данными упирается в то, что до половины экранов ведёт
/// нетривиальный путь — вход, разрешение на уведомления, свайп, модальное окно.
/// Замыкание честно признаёт, что это код, и оставляет его в тесте, где ему
/// и место.
public struct WalkPlan {
    public struct Step {
        public let screen: String

        /// Шаг сам приводит приложение в нужное состояние, откуда бы
        /// ни стартовал.
        ///
        /// Различие не косметическое, оно решает, что делать с упавшим шагом.
        /// Нажатие вкладки самодостаточно: вкладка доступна с любого экрана,
        /// поэтому провал одной вкладки ничего не говорит о следующей и обход
        /// должен идти дальше. Шаг, который углубляется от текущего места,
        /// самодостаточным не является: после его провала мы не знаем, где
        /// находимся, и все дальнейшие шаги снимали бы случайный экран.
        public let anchored: Bool

        public let navigate: (XCUIApplication) throws -> Void

        /// Уточняет имя экрана уже ПОСЛЕ перехода.
        ///
        /// Нужно там, где имя заранее неизвестно: при обходе чужого
        /// приложения мы не знаем, как называется раздел, пока в него
        /// не вошли. Первая попытка решала это разведкой — обход прогонялся
        /// дважды, первый раз ради названий. Разведка сломала «Фото»: она
        /// оставляла приложение на вкладке «Поиск» с поднятой клавиатурой,
        /// после чего вкладки переставали быть доступны и обход снимал
        /// НОЛЬ экранов вместо трёх. Считывание имени после перехода даёт
        /// тот же результат без второго прохода и без порчи состояния.
        public let resolveName: ((XCUIApplication) -> String?)?

        public init(
            screen: String,
            anchored: Bool = false,
            resolveName: ((XCUIApplication) -> String?)? = nil,
            navigate: @escaping (XCUIApplication) throws -> Void
        ) {
            self.screen = screen
            self.anchored = anchored
            self.resolveName = resolveName
            self.navigate = navigate
        }
    }

    public let steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }
}

/// Снимает базовую линию приложения по сценарию.
@MainActor
public struct BaselineRecorder {

    private let app: XCUIApplication
    private let source: SpeechSource
    private let includePlatformAudit: Bool

    /// - Parameter includePlatformAudit: прогонять ли встроенный
    ///   `performAccessibilityAudit`. По умолчанию да: его находки идут
    ///   в отчёт отдельным разделом и служат границей оплачиваемого.
    public init(app: XCUIApplication, source: SpeechSource, includePlatformAudit: Bool = true) {
        self.app = app
        self.source = source
        self.includePlatformAudit = includePlatformAudit
    }

    public func record(plan: WalkPlan, appVersion: String, locale: String = "ru") throws -> Baseline {
        try source.begin()
        defer { try? source.end() }

        var screens: [ScreenSnapshot] = []
        for step in plan.steps {
            // Неудачная навигация ОСТАНАВЛИВАЕТ обход, но не отменяет прогон.
            //
            // Раньше шаг бросал ошибку наружу, и весь тест прерывался вместе
            // с уже снятыми экранами. Прогон по примеру IQKeyboardManager
            // показал это в чистом виде: с двумя экранами результат был,
            // с тремя — пустой вывод, потому что третий шаг не нашёл, куда
            // нажать, и выбросил всё.
            //
            // Экран, до которого не дошли, — это меньшее покрытие,
            // а не отсутствие результата.
            do {
                try step.navigate(app)
            } catch {
                // Самодостаточный шаг пропускаем и идём дальше: его провал
                // не портит состояние для следующих. Зависимый — обрываем,
                // иначе дальше снимался бы неизвестно какой экран под чужим
                // именем, а это хуже, чем меньшее покрытие.
                if step.anchored { continue }
                break
            }
            let resolved = step.resolveName?(app)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let screenName = (resolved?.isEmpty == false) ? resolved! : step.screen
            var snapshot = try captureStable(named: screenName)

            if includePlatformAudit {
                snapshot.platformAuditFindings = platformAudit(screen: screenName)
            }
            // Экран, совпадающий с уже снятым, в базовую линию не попадает.
            //
            // Найдено прогоном по Pulse: обход не смог уйти вглубь и снял
            // стартовый экран дважды, под именами «Стартовый экран»
            // и «Экран 3». В отчёте это выглядело как одни и те же дефекты
            // на разных экранах, то есть удваивало их число на ровном месте
            // и врало о покрытии приложения.
            let alreadySeen = screens.contains { $0.utterances.map(\.spoken) == snapshot.utterances.map(\.spoken) }
            if alreadySeen { continue }

            screens.append(snapshot)
        }

        return Baseline(
            app: app.label,
            appVersion: appVersion,
            osVersion: osVersion(),
            locale: locale,
            fidelity: source.fidelity,
            capturedOn: Self.today(),
            screens: screens
        )
    }

    /// Снимает экран только после того, как он перестал меняться.
    ///
    /// Навигация возвращает управление, когда нажатие обработано, а не когда
    /// переход дорисовался: `wait(for: .runningForeground)` срабатывает
    /// мгновенно, потому что приложение и так на переднем плане. Снимок
    /// попадал на середину анимации.
    ///
    /// Видно это было только сравнением двух одинаковых прогонов индекса:
    /// у «Просмотра» совпадало число экранов, но не число элементов — 167
    /// против 158, у «Файлов» 150 против 153. То есть обход шёл одинаково,
    /// а снимал разное.
    ///
    /// Признак «дорисовалось» — два одинаковых снимка подряд. Сравниваем
    /// по произносимому тексту: именно он и есть предмет проверки, а координаты
    /// могут дрожать на последних кадрах анимации, ничего не меняя для
    /// человека с VoiceOver.
    private func captureStable(named screen: String, attempts: Int = 5) throws -> ScreenSnapshot {
        var last = try source.captureScreen(named: screen)
        for _ in 0..<attempts {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            let next = try source.captureScreen(named: screen)
            if next.utterances.map(\.spoken) == last.utterances.map(\.spoken) { return next }
            last = next
        }
        // Экран так и не устоялся — берём последний снимок и идём дальше.
        // Это честнее, чем ронять весь прогон из-за одного живого экрана.
        return last
    }

    /// Прогоняет встроенный аудит платформы и переводит его находки
    /// в общую модель.
    ///
    /// Обработчик возвращает true — «находка обработана, тест не валить».
    /// Возврат false означает обратное, и тогда каждый дефект контраста
    /// роняет прогон. Останавливать сборку решает диффер по регрессиям,
    /// а не первая попавшаяся мелочь: инструмент, который краснеет на всём,
    /// выключают через две недели.
    private func platformAudit(screen: String) -> [Finding] {
        var findings: [Finding] = []
        #if os(iOS)
        if #available(iOS 17.0, *) {
            try? app.performAccessibilityAudit { issue in
                findings.append(Finding(
                    key: "\(screen)|platform|\(issue.auditType)|\(issue.element?.identifier ?? issue.compactDescription)",
                    ruleID: "platform-\(issue.auditType)",
                    source: .platformAudit,
                    severity: .moderate,
                    screen: screen,
                    summary: issue.compactDescription,
                    evidence: issue.detailedDescription
                ))
                return true
            }
        }
        #endif
        return findings
    }

    /// Дата съёма в машинном виде. Именно машинном: она попадает в базовую
    /// линию, которая лежит в репозитории и сравнивается между прогонами,
    /// а локализованная дата ломала бы сравнение на другой машине.
    static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
}
#endif
