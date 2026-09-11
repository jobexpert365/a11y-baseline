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

        if ProcessInfo.processInfo.environment["A11Y_DUMP_TREE"] == "1" {
            var lines: [String] = []
            Self.dump(node: root, depth: 0, into: &lines)
            let path = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("tree-\(name).txt")
            try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
            print("A11Y_TREE_DUMP=\(path.path)")
        }

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

        // Системная обвязка вокруг приложения в аудит не входит.
        //
        // Найдено прогоном по Ice Cubes: пять находок оказались клавишами
        // экранной клавиатуры с внутренними именами «Padding-Left»
        // и «Padding-Right». Это интерфейс операционной системы, а не
        // приложения: разработчик его не писал и починить не может,
        // а отчёт с чужими дефектами обесценивает все остальные.
        if Self.isSystemChrome(node.elementType) { return false }

        // Контейнеры не озвучиваются сами — озвучивается их содержимое.
        // Первая версия этого не различала и глотала всё дерево: у окна
        // и панели вкладок есть подпись или роль, поэтому «объявленным
        // целиком» оказывался корень, и на выходе получалось три элемента
        // вместо сотни. Проверено на Food Truck: было 3, стало столько,
        // сколько реально произносится.
        if Self.isContainer(node.elementType) {
            var announcedInside = false
            for child in node.children {
                // Служебные детали ячейки в обход не входят.
                //
                // Картинка внутри ячейки — украшение: VoiceOver сворачивает
                // её в реплику ячейки, в «Настройках» строка читается как
                // «Основные, кнопка», а стрелка отдельно не произносится.
                //
                // Отдельно — указатель раскрытия. В UIKit он приходит не
                // картинкой, а КНОПКОЙ с подписью «chevron»: прогон по примеру
                // IQKeyboardManager дал 27 таких кнопок в одной таблице.
                // Двадцать семь одинаковых реплик — это не дефект приложения,
                // а системная деталь оформления списка.
                //
                // Список имён закрытый и будет пополняться по мере встреч:
                // это честнее широкой эвристики, которая заодно спрячет
                // настоящие дефекты.
                if node.elementType == .cell {
                    if child.elementType == .image { continue }
                    if Self.isCellAccessory(child.label) { continue }
                }
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
        let placeholder = node.placeholderValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        utterances.append(Utterance(
            index: utterances.count,
            spoken: Self.compose(label: label, value: value, placeholder: placeholder, traits: traits),
            label: label.isEmpty ? nil : label,
            value: value,
            traits: traits,
            placeholder: placeholder?.isEmpty == true ? nil : placeholder,
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

    /// Служебные имена указателей и аксессуаров ячейки.
    ///
    /// Это системные детали списка, а не элементы приложения: VoiceOver
    /// их не произносит, а разработчик не может их переименовать.
    static func isCellAccessory(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["chevron", "chevron.forward", "chevron.right", "detail", "reorder", "delete"].contains(normalized)
    }

    /// Части интерфейса операционной системы, наложенные поверх приложения.
    ///
    /// Клавиатура, строка состояния и системные меню принадлежат не тому,
    /// чьё приложение проверяется. Находки о них не действие, а шум: их
    /// невозможно исправить в коде приложения.
    static func isSystemChrome(_ type: XCUIElement.ElementType) -> Bool {
        switch type {
        case .keyboard, .statusBar, .menuBar, .touchBar: true
        default: false
        }
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

    /// Диагностический вывод структуры дерева. Включается переменной
    /// A11Y_DUMP_TREE=1 и нужен ровно для одного: чинить фильтры по факту,
    /// а не по догадке о том, как устроено чужое приложение.
    static func dump(node: XCUIElementSnapshot, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let label = node.label.isEmpty ? "-" : node.label
        let identifier = node.identifier.isEmpty ? "" : " #\(node.identifier)"
        lines.append("\(indent)[\(node.elementType.rawValue)]\(identifier) \(label)")
        for child in node.children {
            dump(node: child, depth: depth + 1, into: &lines)
        }
    }

    /// Собирает реплику так, как её произнёс бы VoiceOver.
    ///
    /// Порядок частей задокументирован Apple: подпись, значение, роль.
    /// Подсказка произносится последней и с задержкой, поэтому в строку
    /// не включается — в базовой линии она давала бы шум при каждом
    /// изменении тайминга.
    static func compose(label: String, value: String?, placeholder: String? = nil, traits: [String]) -> String {
        var parts: [String] = []
        if !label.isEmpty {
            parts.append(label)
        } else if let placeholder, !placeholder.isEmpty {
            // Подсказка звучит вместо подписи, только когда подписи нет.
            parts.append(placeholder)
        }
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
