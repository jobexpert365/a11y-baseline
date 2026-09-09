import Foundation

/// Контекст, в котором правило судит об одной реплике.
///
/// Правилу передаётся весь экран, а не только текущая реплика: часть суждений
/// невозможна локально. Например, «две кнопки звучат одинаково» — это свойство
/// пары, а не элемента.
public struct RuleContext: Sendable {
    public let screen: ScreenSnapshot
    public let locale: String

    public init(screen: ScreenSnapshot, locale: String) {
        self.screen = screen
        self.locale = locale
    }

    /// Признаки, которые считаются интерактивными.
    /// Список намеренно узкий: ложная находка на неинтерактивном элементе
    /// дороже пропущенной, потому что отчёт читает человек, который платит
    /// за доверие к нему.
    public static let interactiveTraits: Set<String> = [
        "button", "link", "searchField", "keyboardKey", "tabBar", "toggle",
        "textField", "slider", "stepper", "picker", "menuItem", "checkBox",
    ]

    public func isInteractive(_ u: Utterance) -> Bool {
        !Set(u.traits).isDisjoint(with: Self.interactiveTraits)
    }
}

/// Правило — это одно суждение о том, что должно было прозвучать.
///
/// Ровно здесь лежит товар. Обход элементов и снятие реплик платформа отдаёт
/// бесплатно (`XCUIVoiceOverService` с iOS 27 возвращает произнесённое как
/// значение функции), а вот ответ на вопрос «правильно ли это произнесено»
/// не отдаёт никто. Поэтому обход в этом пакете открыт и бесплатен, а корпус
/// правил — то, что растёт и накапливается.
public protocol Rule: Sendable {

    /// Стабильный идентификатор, попадает в ключ находки и в принятые
    /// исключения. Менять нельзя — сломает принятые исключения у клиентов.
    static var id: String { get }

    /// На какой пункт стандарта ссылается правило.
    static var standard: StandardRef { get }

    /// Проверяет одну реплику. Возвращает nil, если претензий нет.
    func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding?
}

extension Rule {

    /// Собирает стабильный ключ находки.
    ///
    /// Порядок частей важен: экран → правило → элемент. Элемент опознаётся
    /// идентификатором, если он есть, иначе подписью, и только в крайнем
    /// случае позицией. Позиция едет при любом изменении экрана, поэтому
    /// принятое исключение на такой находке живёт до первой правки — это
    /// осознанный компромисс, а не недосмотр.
    func makeKey(screen: String, utterance: Utterance) -> String {
        let element = switch utterance.matchKey {
        case .identifier(let id): "id:\(id)"
        case .label(let label): "label:\(label)"
        case .position(let index): "pos:\(index)"
        }
        return "\(screen)|\(Self.id)|\(element)"
    }
}
