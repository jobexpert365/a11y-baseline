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

    @Test("поле с подсказкой, но без подписи, блокером не считается")
    func ignoresFieldWithPlaceholder() {
        // Регрессионный тест на ложный блокер, найденный прогоном по Ice Cubes:
        // поле ввода без подписи, но с подсказкой, VoiceOver озвучивает
        // подсказкой, и человек понимает, что от него хотят.
        let u = Utterance(index: 0, spoken: "Адрес сервера, textField", label: nil,
                          traits: ["textField"], placeholder: "Адрес сервера")
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("поле без подписи и без подсказки — блокер")
    func flagsFieldWithoutAnything() {
        let u = Utterance(index: 0, spoken: "textField", label: nil, traits: ["textField"])
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u])))?.severity == .blocker)
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

    @Test("глагол действия — осмысленная подпись",
          arguments: ["Выбрать", "Открыть", "Select", "Open", "Сохранить"])
    func ignoresActionVerbs(label: String) {
        // Регрессионный тест: правило обвиняло кнопку «Выбрать» в «Фото».
        // Глагол точно описывает, что произойдёт при нажатии, — это хорошая
        // подпись, а не заглушка.
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("осмысленная подпись проходит", arguments: ["Отправить отчёт", "Закрыть окно", "Корзина"])
    func ignoresMeaningful(label: String) {
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Имя символа в подписи")
struct SymbolNameLabelRuleTests {

    @Test("настоящие имена символов ловятся",
          arguments: ["chevron.forward", "calendar.day.timeline.leading", "square.and.arrow.up"])
    func flagsSymbolNames(label: String) {
        // calendar.day.timeline.leading — не выдумка: это реальная подпись
        // кнопки в «Календаре» iOS, найденная прогоном.
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(SymbolNameLabelRule().evaluate(u, in: context(screen([u])))?.severity == .serious)
    }

    @Test("дата именем символа не считается", arguments: ["01.01.2001", "12.5.3", "2.0.1"])
    func ignoresDates(label: String) {
        // Регрессионный тест на настоящее ложное срабатывание из «Сообщений»:
        // дата состоит из цифр и точек, как и имя символа. Имена SF Symbol
        // всегда содержат слова.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["button"])
        #expect(SymbolNameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("домен именем символа не считается",
          arguments: ["github.com", "objects-origin.githubusercontent.com", "api.example.io"])
    func ignoresDomains(label: String) {
        // Регрессионный тест на ложное срабатывание из Pulse: сетевой логгер
        // показывает адреса серверов, а они устроены как имена символов —
        // строчные слова через точку. Отличаются доменной зоной на конце.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["button"])
        #expect(SymbolNameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("человеческие подписи и бренды проходят",
          arguments: ["Отправить", "Sonava", "Send", "Календарь на день", "ОК"])
    func ignoresHumanAndBrands(label: String) {
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["button"])
        #expect(SymbolNameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Непереведённая подпись")
struct UntranslatedLabelRuleTests {

    @Test("английское слово в русском приложении даёт мелкую находку-вопрос")
    func asksAboutEnglishWord() {
        let u = Utterance(index: 0, spoken: "Send, button", label: "Send", traits: ["button"])
        let finding = UntranslatedLabelRule().evaluate(u, in: context(screen([u]), locale: "ru"))
        // Уровень намеренно мелкий: бренд от непереведённой подписи машина
        // не отличает, и обвинять здесь нельзя.
        #expect(finding?.severity == .minor)
        #expect(finding?.summary.contains("Проверьте") == true)
    }

    @Test("в англоязычном приложении правило молчит")
    func silentInEnglishApp() {
        let u = Utterance(index: 0, spoken: "Send, button", label: "Send", traits: ["button"])
        #expect(UntranslatedLabelRule().evaluate(u, in: context(screen([u]), locale: "en")) == nil)
    }

    @Test("кнопка с видимым текстом не подозревается")
    func ignoresButtonWithVisibleText() {
        let u = Utterance(index: 0, spoken: "Sonava, button", label: "Sonava",
                          traits: ["button"], visibleText: "Sonava")
        #expect(UntranslatedLabelRule().evaluate(u, in: context(screen([u]), locale: "ru")) == nil)
    }
}

@Suite("Имя файла в подписи")
struct FilenameLabelRuleTests {

    @Test("имена ресурсов ловятся",
          arguments: ["ic_close_24", "arrow-left.png", "IMG_2043", "btn_submit", "dough/brown-thumb"])
    func flagsAssetNames(label: String) {
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("строка запроса именем файла не считается",
          arguments: ["GET /octocat.png", "POST /api/upload.json", "загрузить фото.png"])
    func ignoresRequestLines(label: String) {
        // Регрессионный тест из Pulse: «GET /octocat.png» — это строка
        // HTTP-запроса, показанная по делу, а не утёкшее имя ассета.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("домен именем файла не считается",
          arguments: ["objects-origin.githubusercontent.com", "cdn-assets.example.io"])
    func ignoresDomainsInFilenameRule(label: String) {
        // Регрессионный тест: домен с дефисом проходил проверку «нет пробелов
        // плюс есть разделитель» и попадал в отчёт как имя ассета.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
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
