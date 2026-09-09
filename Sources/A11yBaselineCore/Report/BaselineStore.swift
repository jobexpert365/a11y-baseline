import Foundation

/// Чтение и запись базовой линии.
///
/// Формат — JSON с отсортированными ключами и отступами. Оба параметра
/// обязательны и выбраны не для красоты: базовая линия лежит в репозитории
/// клиента и попадает в код-ревью. Нестабильный порядок ключей превратил бы
/// каждый diff в кашу, а однострочный JSON сделал бы ревью невозможным.
public struct BaselineStore: Sendable {

    public init() {}

    public func encode(_ baseline: Baseline) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(baseline)
    }

    public func decode(_ data: Data) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: data)
    }

    public func write(_ baseline: Baseline, to url: URL) throws {
        try encode(baseline).write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> Baseline {
        try decode(Data(contentsOf: url))
    }
}
