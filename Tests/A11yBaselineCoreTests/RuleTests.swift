import Testing
import Foundation
@testable import A11yBaselineCore

/// Правила — это товар, поэтому тесты здесь проверяют не только срабатывание,
/// но и НЕсрабатывание. Ложная находка в отчёте дороже пропущенной: она
/// подрывает доверие ко всему документу, а пропущенную клиент просто не увидит.

private func screen(_ utterances: [Utterance], name: String = "Главный") -> ScreenSnapshot {
    ScreenSnapshot(screen: name, utterances: utterances)
}

private func context(_ s: ScreenSnapshot, locale: String = "ru") -> RuleContext {
    RuleContext(screen: s, locale: locale)
}

@Suite("Пустая подпись")
struct EmptyUtteranceRuleTests {

    @Test("кнопка без подписи — блокер")
    func flagsUnlabeledButton() {
        let u = Utterance(index: 0, spoken: "button", label: nil, traits: ["button"])
        let s = screen([u])
        let finding = EmptyUtteranceRule().evaluate(u, in: context(s))
        #expect(finding?.severity == .blocker)
        #expect(finding?.fix != nil)
    }

    @Test("текст без подписи не считается находкой")
    func ignoresNonInteractive() {
        let u = Utterance(index: 0, spoken: "", label: nil, traits: [])
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("кнопка с подписью проходит")
    func ignoresLabeledButton() {
        let u = Utterance(index: 0, spoken: "Отправить, button", label: "Отправить", traits: ["button"])
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Бессмысленная подпись")
struct GenericLabelRuleTests {

    @Test("подпись-роль ловится", arguments: ["Кнопка", "button", "изображение", "Untitled", "TODO"])
    func flagsGeneric(label: String) {
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u])))?.severity == .serious)
    }

    @Test("осмысленная подпись проходит", arguments: ["Отправить отчёт", "Закрыть окно", "Корзина"])
    func ignoresMeaningful(label: String) {
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Имя файла в подписи")
struct FilenameLabelRuleTests {

    @Test("имена ресурсов ловятся", arguments: ["ic_close_24", "arrow-left.png", "IMG_2043", "btn_submit"])
    func flagsAssetNames(label: String) {
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("человеческие фразы проходят", arguments: ["Закрыть", "Стрелка назад", "Фото профиля", "ОК"])
    func ignoresHumanText(label: String) {
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Дубликаты подписей")
struct DuplicateLabelRuleTests {

    @Test("три одинаковые кнопки дают ровно одну находку")
    func reportsOncePerGroup() {
        let utterances = (0..<3).map {
            Utterance(index: $0, spoken: "Подробнее, button", label: "Подробнее", traits: ["button"])
        }
        let s = screen(utterances)
        let findings = utterances.compactMap { DuplicateLabelRule().evaluate($0, in: context(s)) }
        #expect(findings.count == 1)
        #expect(findings.first?.utteranceIndex == 0)
    }

    @Test("одинаковая подпись при разных ролях дубликатом не считается")
    func ignoresSameLabelDifferentRole() {
        // Регрессионный тест на настоящее ложное срабатывание, найденное
        // прогоном по «Настройкам» iOS: строка списка «Поиск» и поле поиска
        // «Поиск». VoiceOver произносит роль, поэтому различить их на слух
        // можно, и дефекта здесь нет.
        let utterances = [
            Utterance(index: 0, spoken: "Поиск, button", label: "Поиск", traits: ["button"]),
            Utterance(index: 1, spoken: "Поиск, searchField", label: "Поиск", traits: ["searchField"]),
        ]
        let s = screen(utterances)
        #expect(utterances.compactMap { DuplicateLabelRule().evaluate($0, in: context(s)) }.isEmpty)
    }

    @Test("разные подписи не считаются дубликатами")
    func ignoresDistinct() {
        let utterances = ["Открыть", "Удалить"].enumerated().map {
            Utterance(index: $0.offset, spoken: $0.element, label: $0.element, traits: ["button"])
        }
        let s = screen(utterances)
        #expect(utterances.compactMap { DuplicateLabelRule().evaluate($0, in: context(s)) }.isEmpty)
    }
}

@Suite("Видимая надпись и программное имя")
struct LabelInNameRuleTests {

    @Test("расхождение ловится: на кнопке написано одно, озвучивается другое")
    func flagsMismatch() {
        let u = Utterance(index: 0, spoken: "Продолжить, button", label: "Продолжить",
                          traits: ["button"], visibleText: "Далее")
        #expect(LabelInNameRule().evaluate(u, in: context(screen([u])))?.severity == .serious)
    }

    @Test("видимый текст внутри подписи проходит")
    func ignoresContained() {
        let u = Utterance(index: 0, spoken: "Далее к оплате, button", label: "Далее к оплате",
                          traits: ["button"], visibleText: "Далее")
        #expect(LabelInNameRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("заполненное поле ввода не даёт ложной находки")
    func ignoresTextFieldValue() {
        // Регрессионный тест на настоящий баг: правило брало value как видимую
        // надпись, и каждое заполненное поле становилось находкой.
        let u = Utterance(index: 0, spoken: "Почта, user@example.com, textField",
                          label: "Почта", value: "user@example.com", traits: ["textField"])
        #expect(LabelInNameRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Размер цели нажатия")
struct TargetSizeRuleTests {

    @Test("меньше 24 пт — серьёзно")
    func flagsBelowStandard() {
        let u = Utterance(index: 0, spoken: "Закрыть", label: "Закрыть", traits: ["button"],
                          frame: Rect(x: 0, y: 0, width: 20, height: 20))
        #expect(TargetSizeRule().evaluate(u, in: context(screen([u])))?.severity == .serious)
    }

    @Test("между 24 и 44 пт — мелочь")
    func flagsBelowPlatform() {
        let u = Utterance(index: 0, spoken: "Закрыть", label: "Закрыть", traits: ["button"],
                          frame: Rect(x: 0, y: 0, width: 32, height: 32))
        #expect(TargetSizeRule().evaluate(u, in: context(screen([u])))?.severity == .minor)
    }

    @Test("44 пт и больше проходит")
    func ignoresLargeEnough() {
        let u = Utterance(index: 0, spoken: "Закрыть", label: "Закрыть", traits: ["button"],
                          frame: Rect(x: 0, y: 0, width: 44, height: 44))
        #expect(TargetSizeRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}
