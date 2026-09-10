#if canImport(XCTest) && canImport(XCUIAutomation)
import Foundation
import XCTest
import A11yBaselineCore

/// Источник реплик, работающий на любой версии Xcode.
///
/// Восстанавливает реплику из дерева доступности по правилам композиции
/// VoiceOver: подпись, затем значение, затем роль. Это приближение, и оно
/// честно помечено в базовой линии — настоящий VoiceOver умеет склеивать
/// соседние элементы, сокращать длинные строки и подставлять локализованные
/// названия ролей, которых в дереве нет.
///
/// Приближение при этом полезно: большинство находок — пустая подпись, имя
/// файла в подписи, дубликаты, подпись из имени символа — видны и в нём,
/// потому что они про содержимое, а не про озвучку.
@MainActor
public final class AccessibilityTreeSource: SpeechSource {

    public let fidelity: CaptureFidelity = .accessibilityTree

    private let app: XCUIApplication

    public init(app: XCUIApplication) {
        self.app = app
    }

    public func begin() throws {}
    public func end() throws {}

    public func captureScreen(named name: String) throws -> ScreenSnapshot {
        // Один атомарный снимок всего дерева вместо поэлементных запросов.
        //
        // Так пришлось сделать после падения на живом приложении: перечисление
        // элементов и последующее чтение их свойств — это отдельные запросы
        // к приложению, и если интерфейс успел измениться между ними (анимация,
        // подгрузка данных), XCUITest падает с «Failed to get matching snapshot».
        // На своём демо этого не видно: там статичный экран. На чужом
        // приложении с анимациями — сразу.
        //
        // Побочный и более важный выигрыш: снимок отдаёт НАСТОЯЩУЮ иерархию,
        // а не плоский список. Значит вложенность определяется структурой,
        // а не эвристикой по геометрии.
        let root = try app.snapshot()

        var utterances: [Utterance] = []
        collect(node: root, parentIsAnnounced: false, into: &utterances)

        // Индексы проставляются после обхода: до фильтрации их присваивать
        // нельзя, иначе в базовой линии останутся дыры и правило порядка
        // чтения будет считать позиции неверно.
        for index in utterances.indices {
            utterances[index].index = index
        }

        return ScreenSnapshot(screen: name, utterances: utterances)
    }

    /// Рекурсивно обходит снимок дерева.
    ///
    /// Ключевое решение — параметр `parentIsAnnounced`. VoiceOver, встретив
    /// озвучиваемый элемент с подписью, объявляет его целиком и внутрь
    /// не заходит: ячейка списка произносится одной репликой, а стрелка
    /// и иконки внутри неё отдельно не звучат. Дерево XCUITest устроено иначе
    /// и показывает их как самостоятельные узлы — отсюда и брались находки
    /// про «chevron» в «Настройках» iOS.
    ///
    /// Раньше вложенность угадывалась по геометрии. Теперь она берётся
    /// из структуры, и это точнее: элемент может лежать внутри другого
    /// визуально, не будучи его потомком, и наоборот.
    @discardableResult
    private func collect(
        node: XCUIElementSnapshot,
        parentIsAnnounced: Bool,
        into utterances: inout [Utterance]
    ) -> Bool {
        if parentIsAnnounced { return false }

        // Контейнеры не озвучиваются сами — озвучивается их содержимое.
        // Первая версия этого не различала и глотала всё дерево: у окна
        // и панели вкладок есть подпись или роль, поэтому «объявленным
        // целиком» оказывался корень, и на выходе получалось три элемента
        // вместо сотни. Проверено на Food Truck: было 3, стало столько,
        // сколько реально произносится.
        if Self.isContainer(node.elementType) {
            var announcedInside = false
            for child in node.children {
                // Картинка внутри ячейки — украшение, а не содержимое.
                // VoiceOver сворачивает её в реплику ячейки: в «Настройках»
                // строка читается как «Основные, кнопка», а стрелка-шеврон
                // отдельно не произносится. Дерево XCUITest показывает её
                // как самостоятельный узел, и без этого правила инструмент
                // сообщал о несуществующем дефекте «chevron» у Apple.
                if node.elementType == .cell, child.elementType == .image { continue }
                if collect(node: child, parentIsAnnounced: false, into: &utterances) {
                    announcedInside = true
                }
            }

            // Ячейка — пограничный случай. Если внутри неё ничего своего
            // не озвучилось, VoiceOver произносит саму ячейку одной репликой;
            // если внутри есть кнопки и текст, он читает их, а ячейку
            // отдельно не объявляет.
            if node.elementType == .cell, !announcedInside {
                append(node: node, traits: ["cell"], into: &utterances)
                return true
            }
            return announcedInside
        }

        let traits = [Self.traitName(for: node.elementType)].compactMap { $0 }
        let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty || !traits.isEmpty else {
            // Безымянный неконтейнерный узел сам не звучит, но внутри него
            // может лежать содержимое.
            var announcedInside = false
            for child in node.children {
                if collect(node: child, parentIsAnnounced: false, into: &utterances) {
                    announcedInside = true
                }
            }
            return announcedInside
        }

        append(node: node, traits: traits, into: &utterances)
        return true
    }

    private func append(node: XCUIElementSnapshot, traits: [String], into utterances: inout [Utterance]) {
        let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = node.value as? String
        utterances.append(Utterance(
            index: utterances.count,
            spoken: Self.compose(label: label, value: value, traits: traits),
            label: label.isEmpty ? nil : label,
            value: value,
            traits: traits,
            visibleText: Self.visibleText(of: node, label: label, traits: traits),
            identifier: node.identifier.isEmpty ? nil : node.identifier,
            frame: Rect(
                x: node.frame.origin.x,
                y: node.frame.origin.y,
                width: node.frame.width,
                height: node.frame.height
            )
        ))
    }

    /// Типы, которые служат каркасом экрана, а не его содержимым.
    ///
    /// VoiceOver внутрь них заходит и читает то, что лежит внутри, а сам
    /// контейнер отдельной репликой не объявляет. Список закрытый и короткий:
    /// всё, чего в нём нет, считается содержимым и озвучивается.
    static func isContainer(_ type: XCUIElement.ElementType) -> Bool {
        switch type {
        case .application, .window, .other, .group, .table, .collectionView,
             .scrollView, .navigationBar, .toolbar, .tabBar, .sheet, .alert,
             .dialog, .cell, .outline, .layoutArea, .layoutItem, .splitGroup, .drawer:
            true
        default:
            false
        }
    }

    /// Видимый текст элемента, если его можно отличить от подписи не гадая.
    ///
    /// Единственный надёжный случай — кнопка с текстовым потомком: то, что
    /// человек видит на кнопке, лежит в этом потомке, а подпись задана
    /// отдельно. Для остальных типов вернуть нечего, и правило совпадения
    /// надписи с именем просто промолчит.
    private static func visibleText(
        of node: XCUIElementSnapshot,
        label: String,
        traits: [String]
    ) -> String? {
        guard traits.contains("button") || traits.contains("link") else { return nil }
        let text = node.children
            .first { $0.elementType == .staticText && !$0.label.isEmpty }?
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty, text != label else { return nil }
        return text
    }

    /// Собирает реплику так, как её произнёс бы VoiceOver.
    ///
    /// Порядок частей задокументирован Apple: подпись, значение, роль.
    /// Подсказка произносится последней и с задержкой, поэтому в строку
    /// не включается — в базовой линии она давала бы шум при каждом
    /// изменении тайминга.
    static func compose(label: String, value: String?, traits: [String]) -> String {
        var parts: [String] = []
        if !label.isEmpty { parts.append(label) }
        if let value, !value.isEmpty, value != label { parts.append(value) }
        parts.append(contentsOf: traits)
        return parts.joined(separator: ", ")
    }

    /// Сопоставление типа элемента с названием роли.
    ///
    /// Список неполный намеренно: сюда включены только типы, которые VoiceOver
    /// действительно объявляет вслух. Для остальных роль не произносится,
    /// и добавлять её в реплику значит врать.
    static func traitName(for type: XCUIElement.ElementType) -> String? {
        switch type {
        case .button: "button"
        case .link: "link"
        case .image: "image"
        case .searchField: "searchField"
        case .textField, .secureTextField: "textField"
        case .switch: "toggle"
        case .slider: "slider"
        case .stepper: "stepper"
        case .checkBox: "checkBox"
        case .tab, .tabBar: "tabBar"
        case .menuItem: "menuItem"
        case .key: "keyboardKey"
        default: nil
        }
    }
}
#endif
