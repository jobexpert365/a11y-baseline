import Foundation

/// Снимок одного экрана: последовательность реплик в порядке обхода.
public struct ScreenSnapshot: Codable, Equatable, Sendable {

    /// Человекочитаемое имя экрана, задаётся сценарием съёма.
    public var screen: String

    /// Реплики в порядке обхода.
    public var utterances: [Utterance]

    /// Находки встроенного аудита платформы (`performAccessibilityAudit`),
    /// снятые на этом же экране.
    ///
    /// Они хранятся отдельно от находок движка правил и в отчёте показываются
    /// отдельным разделом. Причина не косметическая: платформа раздаёт этот
    /// аудит бесплатно, и смешивать его со своими находками — значит продавать
    /// чужое. Разделение делает границу оплачиваемого видимой глазами.
    public var platformAuditFindings: [Finding]

    public init(screen: String, utterances: [Utterance], platformAuditFindings: [Finding] = []) {
        self.screen = screen
        self.utterances = utterances
        self.platformAuditFindings = platformAuditFindings
    }
}

/// Чем снята базовая линия. Влияет на то, можно ли сравнивать два прогона.
public enum CaptureFidelity: String, Codable, Sendable {

    /// Реплики получены от настоящего VoiceOver через `XCUIVoiceOverService`.
    /// Требует iOS 27 и сборки с флагом `A11Y_VOICEOVER_API`.
    case voiceOverService

    /// Реплики восстановлены из дерева доступности по правилам композиции
    /// VoiceOver. Работает на любой версии, но это приближение: реальный
    /// VoiceOver может склеивать, сокращать и переупорядочивать.
    case accessibilityTree

    /// Данные загружены из фикстуры. Только для тестов.
    case fixture
}

/// Базовая линия приложения: набор снимков экранов плюс контекст съёма.
///
/// Это и есть накапливаемый актив. Код копируется за вечер, базовая линия —
/// нет: в ней лежит история того, как приложение звучало на каждом релизе,
/// и принятые исключения.
public struct Baseline: Codable, Equatable, Sendable {

    /// Версия формата. Меняется только при несовместимых изменениях схемы,
    /// чтобы старые базовые линии не читались молча неправильно.
    public var formatVersion: Int

    public var app: String
    public var appVersion: String
    public var osVersion: String
    public var locale: String
    public var fidelity: CaptureFidelity

    /// Когда приложение реально просканировали, в формате «2026-09-12».
    ///
    /// Поле появилось после того, как я заметил тихую подмену: страница
    /// показывала дату СБОРКИ СТРАНИЦ, а данные могли быть недельной
    /// давности. Пересобрал сайт, не пересканировав ничего, — и все страницы
    /// стали выглядеть свежими. Это ровно тот вид вранья, который незаметен
    /// изнутри и очевиден снаружи, когда кто-то сверит цифры со своим
    /// приложением.
    ///
    /// Необязательное: базовые линии, снятые до этой правки, даты не имеют,
    /// и страница честно скажет, что дата неизвестна.
    public var capturedOn: String?

    public var screens: [ScreenSnapshot]

    /// Ключи находок, которые команда осознанно приняла и не хочет видеть снова.
    /// Хранятся вместе с базовой линией, а не в конфиге, потому что принятое
    /// исключение имеет смысл только применительно к конкретному состоянию
    /// приложения.
    public var acceptedFindingKeys: Set<String>

    public static let currentFormatVersion = 1

    public init(
        formatVersion: Int = Baseline.currentFormatVersion,
        app: String,
        appVersion: String,
        osVersion: String,
        locale: String,
        fidelity: CaptureFidelity,
        capturedOn: String? = nil,
        screens: [ScreenSnapshot],
        acceptedFindingKeys: Set<String> = []
    ) {
        self.formatVersion = formatVersion
        self.app = app
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.locale = locale
        self.fidelity = fidelity
        self.capturedOn = capturedOn
        self.screens = screens
        self.acceptedFindingKeys = acceptedFindingKeys
    }
}
