import Foundation

/// Результат сравнения двух базовых линий.
public struct DiffResult: Equatable, Sendable {
    public var changes: [Change]

    /// Регрессии — изменения, которые ухудшили доступность.
    public var regressions: [Change] { changes.filter(\.isRegression) }

    public var isClean: Bool { regressions.isEmpty }

    public struct Change: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Элемент перестал озвучиваться осмысленно.
            case utteranceLost(was: String)
            /// Реплика изменилась. Не обязательно плохо — текст могли просто
            /// переписать, поэтому такое изменение регрессией не считается,
            /// пока правила не скажут обратное.
            case utteranceChanged(was: String, now: String)
            /// Элемент исчез из обхода целиком.
            case elementDisappeared(was: String)
            /// Появился новый элемент.
            case elementAppeared(now: String)
            /// Элемент переехал в порядке обхода.
            case reordered(from: Int, to: Int)
            /// Появилась новая находка правил.
            case newFinding(Finding)
        }

        public var kind: Kind
        public var screen: String
        public var matchedReliably: Bool

        /// Регрессия — это то, из-за чего стоит останавливать сборку.
        ///
        /// Появление элементов и переписанный текст сюда не входят намеренно:
        /// иначе каждый релиз с новой функцией будет «красным», проверка
        /// обесценится и её выключат. Инструмент, который кричит на всё,
        /// перестают слушать за две недели.
        public var isRegression: Bool {
            switch kind {
            case .utteranceLost, .elementDisappeared:
                true
            case .newFinding(let finding):
                finding.severity >= .serious
            case .utteranceChanged, .elementAppeared, .reordered:
                false
            }
        }
    }
}

/// Сравнивает новый прогон с сохранённой базовой линией.
public struct BaselineDiffer: Sendable {

    public init() {}

    public enum DiffError: Error, Equatable {
        /// Базовые линии сняты разными способами и несравнимы.
        ///
        /// Это не педантизм: приближение по дереву доступности и реальный
        /// VoiceOver дают разные строки для одного и того же элемента, и их
        /// сравнение даст сотни ложных регрессий на ровном месте.
        case fidelityMismatch(baseline: CaptureFidelity, current: CaptureFidelity)

        /// Формат базовой линии из будущей версии пакета.
        case unsupportedFormat(Int)
    }

    public func diff(baseline: Baseline, current: Baseline, rules: RuleRegistry = .standard) throws -> DiffResult {
        guard baseline.formatVersion <= Baseline.currentFormatVersion else {
            throw DiffError.unsupportedFormat(baseline.formatVersion)
        }
        guard baseline.fidelity == current.fidelity else {
            throw DiffError.fidelityMismatch(baseline: baseline.fidelity, current: current.fidelity)
        }

        var changes: [DiffResult.Change] = []

        let baselineScreens = Dictionary(uniqueKeysWithValues: baseline.screens.map { ($0.screen, $0) })
        let currentScreens = Dictionary(uniqueKeysWithValues: current.screens.map { ($0.screen, $0) })

        for (name, currentScreen) in currentScreens.sorted(by: { $0.key < $1.key }) {
            guard let baselineScreen = baselineScreens[name] else { continue }
            changes += compare(baseline: baselineScreen, current: currentScreen)
        }

        // Новые находки правил считаются отдельно: элемент мог не измениться,
        // но появиться в отчёте из-за нового правила в реестре.
        let knownKeys = Set(rules.run(on: baseline).map(\.key))
        for finding in rules.run(on: current) where !knownKeys.contains(finding.key) {
            changes.append(.init(kind: .newFinding(finding), screen: finding.screen, matchedReliably: true))
        }

        return DiffResult(changes: changes)
    }

    private func compare(baseline: ScreenSnapshot, current: ScreenSnapshot) -> [DiffResult.Change] {
        var changes: [DiffResult.Change] = []

        let baselineByKey = index(baseline.utterances)
        let currentByKey = index(current.utterances)

        for (key, old) in baselineByKey.sorted(by: { $0.value.index < $1.value.index }) {
            guard let new = currentByKey[key] else {
                changes.append(.init(
                    kind: .elementDisappeared(was: old.spoken),
                    screen: baseline.screen,
                    matchedReliably: key.isReliable
                ))
                continue
            }

            let oldMeaningful = (old.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let newMeaningful = (new.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !oldMeaningful.isEmpty && newMeaningful.isEmpty {
                changes.append(.init(
                    kind: .utteranceLost(was: old.spoken),
                    screen: baseline.screen,
                    matchedReliably: key.isReliable
                ))
            } else if old.spoken != new.spoken {
                changes.append(.init(
                    kind: .utteranceChanged(was: old.spoken, now: new.spoken),
                    screen: baseline.screen,
                    matchedReliably: key.isReliable
                ))
            }

            if old.index != new.index {
                changes.append(.init(
                    kind: .reordered(from: old.index, to: new.index),
                    screen: baseline.screen,
                    matchedReliably: key.isReliable
                ))
            }
        }

        for (key, new) in currentByKey.sorted(by: { $0.value.index < $1.value.index }) where baselineByKey[key] == nil {
            changes.append(.init(
                kind: .elementAppeared(now: new.spoken),
                screen: current.screen,
                matchedReliably: key.isReliable
            ))
        }

        return changes
    }

    /// Индексирует реплики по ключу сопоставления.
    ///
    /// При коллизии ключей побеждает первая реплика: две кнопки с одинаковой
    /// подписью и без идентификаторов различить нечем, и попытка «умного»
    /// сопоставления здесь даёт больше вреда, чем пользы. Само наличие такой
    /// коллизии — отдельная находка, её сообщает DuplicateLabelRule.
    private func index(_ utterances: [Utterance]) -> [Utterance.MatchKey: Utterance] {
        var result: [Utterance.MatchKey: Utterance] = [:]
        for utterance in utterances where result[utterance.matchKey] == nil {
            result[utterance.matchKey] = utterance
        }
        return result
    }
}
