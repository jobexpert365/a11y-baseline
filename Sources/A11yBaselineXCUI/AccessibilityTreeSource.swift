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

        var utterances: [Utterance] = []
        utterances.reserveCapacity(elements.count)

        for (index, element) in elements.enumerated() {
            guard element.isHittable || !element.label.isEmpty else { continue }

            let label = element.label
            let value = element.value as? String
            let traits = [Self.traitName(for: element.elementType)].compactMap { $0 }

            // Видимую надпись берём только у интерактивных элементов и только
            // из текстового потомка. Это единственный случай, когда её можно
            // отличить от подписи не гадая: кнопка с текстом внутри.
            let visibleText: String? = if traits.contains("button") || traits.contains("link") {
                element.staticTexts.allElementsBoundByIndex.first?.label
            } else {
                nil
            }

            utterances.append(Utterance(
                index: index,
                spoken: Self.compose(label: label, value: value, traits: traits),
                label: label.isEmpty ? nil : label,
                value: value,
                traits: traits,
                visibleText: visibleText.flatMap { $0 == label ? nil : $0 },
                identifier: element.identifier.isEmpty ? nil : element.identifier,
                frame: Rect(
                    x: element.frame.origin.x,
                    y: element.frame.origin.y,
                    width: element.frame.width,
                    height: element.frame.height
                )
            ))
        }

        return ScreenSnapshot(screen: name, utterances: utterances)
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
