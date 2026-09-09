import Foundation

/// Одна реплика — то, что скринридер произносит, оказавшись на элементе.
///
/// Это центральный тип всего пакета. Всё остальное либо производит реплики
/// (слой съёма), либо о них судит (движок правил), либо сравнивает две
/// последовательности реплик между собой (диффер).
public struct Utterance: Codable, Equatable, Sendable {

    /// Порядковый номер в обходе, начиная с нуля.
    /// Именно порядок, а не координаты: VoiceOver ходит по логическому
    /// порядку чтения, который может не совпадать с расположением на экране,
    /// и расхождение этих двух порядков — самостоятельная находка.
    public var index: Int

    /// Полный текст реплики целиком, как его слышит человек:
    /// подпись, значение, признак («кнопка», «изображение»), подсказка.
    public var spoken: String

    /// Разобранные части реплики. Заполняются, когда источник умеет их отдать
    /// по отдельности; при съёме через реальный VoiceOver части приходится
    /// восстанавливать эвристически, поэтому поля необязательные.
    public var label: String?
    public var value: String?
    public var traits: [String]
    public var hint: String?

    /// Текст, который человек ВИДИТ на элементе, если он отличается от подписи.
    ///
    /// Отдельное поле, а не `value`, и это не педантизм. У поля ввода `value`
    /// — введённый текст, у слайдера — число. Если считать их видимой надписью,
    /// правило совпадения надписи и имени срабатывает на каждом заполненном
    /// поле, то есть отчёт заполняется мусором ровно там, где приложение
    /// в порядке.
    ///
    /// Заполняется только когда источник может надёжно отличить видимый текст
    /// от подписи — например, взяв текстового потомка у кнопки. Если отличить
    /// нельзя, поле остаётся пустым, и правило просто не срабатывает: молчать
    /// правильнее, чем гадать.
    public var visibleText: String?

    /// Идентификатор элемента, если разработчик его проставил.
    /// Нужен для сопоставления элементов между прогонами: подпись может
    /// поменяться (это и есть находка), а идентификатор обычно нет.
    public var identifier: String?

    /// Прямоугольник элемента в координатах экрана. Используется правилом
    /// размера цели нажатия и правилом порядка чтения.
    public var frame: Rect?

    public init(
        index: Int,
        spoken: String,
        label: String? = nil,
        value: String? = nil,
        traits: [String] = [],
        hint: String? = nil,
        visibleText: String? = nil,
        identifier: String? = nil,
        frame: Rect? = nil
    ) {
        self.index = index
        self.spoken = spoken
        self.label = label
        self.value = value
        self.traits = traits
        self.hint = hint
        self.visibleText = visibleText
        self.identifier = identifier
        self.frame = frame
    }

    /// Ключ сопоставления между прогонами.
    ///
    /// Порядок намеренный: идентификатор устойчив к правкам текста, поэтому
    /// он первый. Если идентификатора нет — сопоставляем по подписи. Если нет
    /// и её, элемент опознаётся только позицией в обходе, и диффер честно
    /// помечает такое сопоставление как ненадёжное.
    public var matchKey: MatchKey {
        if let identifier, !identifier.isEmpty { return .identifier(identifier) }
        if let label, !label.isEmpty { return .label(label) }
        return .position(index)
    }

    public enum MatchKey: Hashable, Sendable {
        case identifier(String)
        case label(String)
        case position(Int)

        /// Сопоставление по позиции — это догадка, а не факт.
        public var isReliable: Bool {
            if case .position = self { return false }
            return true
        }
    }
}

/// Собственный прямоугольник вместо CGRect: Core не тянет CoreGraphics,
/// чтобы собираться на Linux.
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Double { width * height }
    public var minSide: Double { min(width, height) }
}
