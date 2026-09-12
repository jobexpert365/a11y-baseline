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
        public let navigate: (XCUIApplication) throws -> Void

        public init(screen: String, navigate: @escaping (XCUIApplication) throws -> Void) {
            self.screen = screen
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
                break
            }
            var snapshot = try source.captureScreen(named: step.screen)

            if includePlatformAudit {
                snapshot.platformAuditFindings = platformAudit(screen: step.screen)
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
