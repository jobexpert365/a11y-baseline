#if canImport(XCTest) && canImport(XCUIAutomation)
import Foundation
import XCTest
import A11yBaselineCore

/// Источник реплик, работающий на любой версии Xcode.
///
/// Обходит дерево доступности и собирает реплику по правилам композиции
/// VoiceOver: подпись, затем значение, затем роль, затем подсказка. Это
/// приближение, и оно честно помечено как приближение — настоящий VoiceOver
/// умеет склеивать соседние элементы, сокращать длинные строки и подставлять
/// локализованные названия ролей, которых в дереве нет.
///
/// Приближение при этом полезно: подавляющее большинство находок — пустая
/// подпись, имя файла в подписи, дубликаты, несовпадение видимой надписи —
/// видны и в нём, потому что они про содержимое, а не про озвучку.
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
        // descendants(matching: .any) отдаёт элементы в порядке иерархии,
        // и это ровно тот порядок, в котором по ним пойдёт VoiceOver, если
        // приложение не переопределяло accessibilityElements.
        let elements = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .filter(\.exists)

        // Сначала собираем сырые кандидаты, потом отсеиваем вложенные.
        // Разделение нужно, потому что решение «пропустить элемент» зависит
        // от других элементов, а не только от него самого.
        var raw: [(label: String, value: String?, traits: [String], identifier: String, rect: Rect)] = []

        for element in elements {
            // Контейнеры без подписи и без роли VoiceOver не объявляет —
            // включать их в обход значит зашумлять базовую линию и сдвигать
            // отсчёт позиций в правиле порядка чтения.
            let elementTraits = [Self.traitName(for: element.elementType)].compactMap { $0 }
            guard !element.label.isEmpty || !elementTraits.isEmpty else { continue }

            raw.append((
                label: element.label,
                value: element.value as? String,
                traits: elementTraits,
                identifier: element.identifier,
                rect: Rect(
                    x: element.frame.origin.x,
                    y: element.frame.origin.y,
                    width: element.frame.width,
                    height: element.frame.height
                )
            ))
        }

        let kept = Self.dropGroupedChildren(raw)

        var utterances: [Utterance] = []
        utterances.reserveCapacity(kept.count)
        for (index, item) in kept.enumerated() {
            utterances.append(Utterance(
                index: index,
                spoken: Self.compose(label: item.label, value: item.value, traits: item.traits),
                label: item.label.isEmpty ? nil : item.label,
                value: item.value,
                traits: item.traits,
                identifier: item.identifier.isEmpty ? nil : item.identifier,
                frame: item.rect
            ))
        }

        return ScreenSnapshot(screen: name, utterances: utterances)
    }

    /// Отсеивает элементы, которые VoiceOver объявляет не отдельно, а вместе
    /// с родителем.
    ///
    /// Найдено измерением, а не придумано. Первый прогон по «Настройкам» iOS
    /// дал находки на элементах с подписью «chevron» — это стрелки в ячейках
    /// списка. VoiceOver их отдельно не произносит: он объявляет ячейку целиком,
    /// а стрелку сворачивает внутрь. Дерево XCUITest устроено иначе и показывает
    /// их как самостоятельные элементы, поэтому приближение по дереву видело
    /// дефекты там, где для слушающего человека их нет.
    ///
    /// Признак вложенности — геометрия: элемент целиком лежит внутри другого,
    /// который сам является озвучиваемым и заметно больше. Это эвристика,
    /// а не точное правило, и она намеренно консервативная: родитель должен
    /// быть минимум вдвое больше по площади, иначе два элемента одного размера
    /// начнут поглощать друг друга.
    static func dropGroupedChildren(
        _ items: [(label: String, value: String?, traits: [String], identifier: String, rect: Rect)]
    ) -> [(label: String, value: String?, traits: [String], identifier: String, rect: Rect)] {
        items.enumerated().filter { index, item in
            guard item.rect.area > 0 else { return true }

            let hasGroupingParent = items.enumerated().contains { otherIndex, other in
                guard otherIndex != index,
                      !other.label.isEmpty,
                      other.rect.area >= item.rect.area * 2 else { return false }
                return other.rect.contains(item.rect)
            }
            return !hasGroupingParent
        }.map(\.element)
    }

    /// Собирает реплику так, как её произнёс бы VoiceOver.
    ///
    /// Порядок частей — не догадка, он задокументирован Apple: сначала
    /// подпись, затем значение, затем роль. Подсказка произносится последней
    /// и с задержкой, поэтому в строку не включается: в базовой линии она
    /// давала бы шум при каждом изменении тайминга.
    static func compose(label: String, value: String?, traits: [String]) -> String {
        var parts: [String] = []
        if !label.isEmpty { parts.append(label) }
        if let value, !value.isEmpty, value != label { parts.append(value) }
        parts.append(contentsOf: traits)
        return parts.joined(separator: ", ")
    }

    /// Сопоставление типа элемента XCUITest с названием роли.
    ///
    /// Список неполный намеренно: сюда включены только те типы, которые
    /// VoiceOver действительно объявляет вслух. Для остальных роль не
    /// произносится, и добавлять её в реплику значит врать.
    static func traitName(for type: XCUIElement.ElementType) -> String? {
        switch type {
        case .button: "button"
        case .link: "link"
        case .image: "image"
        case .searchField: "searchField"
        case .textField, .secureTextField: "textField"
        case .staticText: nil
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
