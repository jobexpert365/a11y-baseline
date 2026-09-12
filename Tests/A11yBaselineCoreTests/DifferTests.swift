import Testing
import Foundation
@testable import A11yBaselineCore

@Suite("Сравнение с базовой линией")
struct BaselineDifferTests {

    private func baseline(_ utterances: [Utterance], fidelity: CaptureFidelity = .fixture) -> Baseline {
        Baseline(
            app: "Demo", appVersion: "1.0", osVersion: "18.0", locale: "ru",
            fidelity: fidelity,
            screens: [ScreenSnapshot(screen: "Главный", utterances: utterances)]
        )
    }

    @Test("потеря подписи — регрессия")
    func lostLabelIsRegression() throws {
        let before = baseline([Utterance(index: 0, spoken: "Отправить, button", label: "Отправить", traits: ["button"], identifier: "send")])
        let after = baseline([Utterance(index: 0, spoken: "button", label: nil, traits: ["button"], identifier: "send")])

        let result = try BaselineDiffer().diff(baseline: before, current: after)
        // Регрессий здесь ровно две, и обе законные: элемент перестал
        // озвучиваться, и на нём появилась находка правила о пустой подписи.
        // Проверяем именно наличие потери речи, а не их общее количество.
        #expect(!result.isClean)
        #expect(result.regressions.contains { if case .utteranceLost = $0.kind { true } else { false } })
        #expect(result.regressions.contains { if case .newFinding = $0.kind { true } else { false } })
    }

    @Test("переписанный текст регрессией не считается")
    func rewordingIsNotRegression() throws {
        let before = baseline([Utterance(index: 0, spoken: "Отправить, button", label: "Отправить", traits: ["button"], identifier: "send")])
        let after = baseline([Utterance(index: 0, spoken: "Отправить отчёт, button", label: "Отправить отчёт", traits: ["button"], identifier: "send")])

        let result = try BaselineDiffer().diff(baseline: before, current: after)
        #expect(result.isClean)
        #expect(result.changes.contains { if case .utteranceChanged = $0.kind { true } else { false } })
    }

    @Test("новый элемент регрессией не считается")
    func additionIsNotRegression() throws {
        let before = baseline([Utterance(index: 0, spoken: "Отправить", label: "Отправить", traits: ["button"], identifier: "send")])
        let after = baseline([
            Utterance(index: 0, spoken: "Отправить", label: "Отправить", traits: ["button"], identifier: "send"),
            Utterance(index: 1, spoken: "Отмена", label: "Отмена", traits: ["button"], identifier: "cancel"),
        ])

        let result = try BaselineDiffer().diff(baseline: before, current: after)
        #expect(result.isClean)
    }

    @Test("линии разной точности сравнивать нельзя")
    func rejectsFidelityMismatch() {
        let before = baseline([], fidelity: .accessibilityTree)
        let after = baseline([], fidelity: .voiceOverService)

        #expect(throws: BaselineDiffer.DiffError.fidelityMismatch(baseline: .accessibilityTree, current: .voiceOverService)) {
            try BaselineDiffer().diff(baseline: before, current: after)
        }
    }

    @Test("исчезнувший элемент — регрессия")
    func disappearanceIsRegression() throws {
        let before = baseline([Utterance(index: 0, spoken: "Отправить", label: "Отправить", traits: ["button"], identifier: "send")])
        let after = baseline([])

        let result = try BaselineDiffer().diff(baseline: before, current: after)
        #expect(result.regressions.count == 1)
    }
}

@Suite("Сохранение базовой линии")
struct BaselineStoreTests {

    @Test("цикл записи и чтения не теряет данных")
    func roundTrip() throws {
        let original = Baseline(
            app: "Demo", appVersion: "2.1", osVersion: "18.0", locale: "ru",
            fidelity: .accessibilityTree,
            screens: [ScreenSnapshot(screen: "Главный", utterances: [
                Utterance(index: 0, spoken: "Войти, button", label: "Войти", traits: ["button"], identifier: "login",
                          frame: Rect(x: 16, y: 100, width: 120, height: 44))
            ])],
            acceptedFindingKeys: ["Главный|target-size|id:login"]
        )

        let store = BaselineStore()
        let restored = try store.decode(store.encode(original))
        #expect(restored == original)
    }

    @Test("ключи в файле отсортированы — иначе ревью превращается в кашу")
    func stableKeyOrder() throws {
        let baseline = Baseline(
            app: "Demo", appVersion: "1.0", osVersion: "18.0", locale: "ru",
            fidelity: .fixture, screens: []
        )
        let json = try #require(String(data: BaselineStore().encode(baseline), encoding: .utf8))
        let appIndex = try #require(json.range(of: "\"app\""))
        let localeIndex = try #require(json.range(of: "\"locale\""))
        #expect(appIndex.lowerBound < localeIndex.lowerBound)
    }
}

@Suite("Дата проверки")
struct CapturedOnTests {

    @Test("дата съёма переживает запись и чтение")
    func survivesRoundTrip() throws {
        let baseline = Baseline(
            app: "Demo", appVersion: "1.0", osVersion: "26.0", locale: "ru",
            fidelity: .fixture, capturedOn: "2026-09-12", screens: []
        )
        let restored = try BaselineStore().decode(BaselineStore().encode(baseline))
        #expect(restored.capturedOn == "2026-09-12")
    }

    @Test("старая базовая линия без даты читается")
    func readsLegacyBaseline() throws {
        // Базовые линии, снятые до появления поля, должны читаться,
        // а не ломать сборку индекса: иначе одна правка схемы обнуляет
        // всю накопленную историю.
        let legacy = """
        {"app":"Demo","appVersion":"1.0","osVersion":"26.0","locale":"ru",
         "fidelity":"fixture","formatVersion":1,"screens":[],"acceptedFindingKeys":[]}
        """
        let restored = try BaselineStore().decode(Data(legacy.utf8))
        #expect(restored.capturedOn == nil)
    }
}
