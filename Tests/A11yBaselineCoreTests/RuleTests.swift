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
        // Экран собираем из русских подписей: правило судит о непереводе
        // только там, где перевод доказанно есть. Одинокая реплика такого
        // доказательства не даёт, и раньше этот тест проходил на ней зря.
        var us = (0..<6).map {
            Utterance(index: $0, spoken: "Кнопка \($0), button", label: "Кнопка \($0)", traits: ["button"])
        }
        let u = Utterance(index: 6, spoken: "Send, button", label: "Send", traits: ["button"])
        us.append(u)
        let finding = UntranslatedLabelRule().evaluate(u, in: context(screen(us), locale: "ru"))
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

    @Test("слово через дефис именем ресурса не считается",
          arguments: ["Блиц-приложения", "БЕТА-ВЕРСИЯ", "Что-нибудь", "по-русски", "up-to-date"])
    func ignoresHyphenatedWords(label: String) {
        // Регрессионный тест из Настроек: проверка «нет пробелов плюс есть
        // разделитель» принимала за имя ассета любое слово через дефис.
        // В русском языке это обычная типографика, а не утёкший идентификатор.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("название приложения именем ресурса не считается",
          arguments: ["Kingfisher-Demo", "ChartsDemo-iOS", "A11yScannerUITests-Runner"])
    func ignoresAppNames(label: String) {
        // Регрессионный тест из Настроек: углублённый обход дошёл до списка
        // установленных приложений, и правило обвинило их собственные имена.
        // Имя приложения выглядит как идентификатор, но оно и есть то, что
        // человек должен услышать.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("косая черта остаётся признаком пути",
          arguments: ["dough/brown-thumb", "topping/sprinkles-stars-thumb", "glaze/rainbow-thumb"])
    func keepsSlashPaths(label: String) {
        // Обратная страховка к правке выше: 77 настоящих находок Food Truck
        // держатся именно на косой черте. Один раз это уже ломалось молча.
        let u = Utterance(index: 0, spoken: label, label: label, traits: ["image"])
        #expect(FilenameLabelRule().evaluate(u, in: context(screen([u]))) != nil)
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

@Suite("Роль в подписи")
struct RoleInLabelRuleTests {

    @Test("роль последним словом ловится", arguments: ["Отправить кнопка", "Send button", "Профиль ссылка"])
    func flagsTrailingRole(label: String) {
        let trait = label.lowercased().hasSuffix("ссылка") ? "link" : "button"
        let u = Utterance(index: 0, spoken: "\(label), \(trait)", label: label, traits: [trait])
        #expect(RoleInLabelRule().evaluate(u, in: context(screen([u])))?.severity == .moderate)
    }

    @Test("длинное описание, случайно оканчивающееся на роль, не ловится",
          arguments: ["Top float with a picture and one button",
                      "Всплывающее окно с картинкой и одной кнопкой",
                      "Выбор действия через нижнюю кнопку"])
    func ignoresLongDescription(label: String) {
        // Регрессионный тест на первое же срабатывание правила в живом
        // приложении — и оно оказалось ложным. «one button» в этой фразе
        // описывает устройство попапа, а не роль элемента.
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(RoleInLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("роль не последним словом — законное название",
          arguments: ["Кнопка вызова экстренных служб", "Кнопка отправить", "Красная кнопка тревоги"])
    func ignoresRoleNotAtEnd(label: String) {
        // Сужение по итогу провалившегося теста. «Кнопка вызова экстренных
        // служб» — нормальное название, где слово несёт смысл. Отличить его
        // от «Кнопка отправить» можно только грамматикой, поэтому правило
        // молчит в обоих случаях: ложное обвинение дороже пропуска.
        let u = Utterance(index: 0, spoken: "\(label), button", label: label, traits: ["button"])
        #expect(RoleInLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("подпись из одного слова — не этот случай")
    func ignoresSingleWord() {
        // «Кнопка» целиком ловит GenericLabelRule: там роль стоит ВМЕСТО
        // назначения, а не рядом с ним.
        let u = Utterance(index: 0, spoken: "Кнопка, button", label: "Кнопка", traits: ["button"])
        #expect(RoleInLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("роль не совпадает с признаком — молчим")
    func ignoresMismatchedRole() {
        // «Ссылка на профиль» на КНОПКЕ: слово «ссылка» роли кнопки
        // не дублирует, VoiceOver скажет «Ссылка на профиль, кнопка».
        let u = Utterance(index: 0, spoken: "Ссылка на профиль, button", label: "Ссылка на профиль", traits: ["button"])
        #expect(RoleInLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("правка убирает слово роли с конца")
    func fixStripsRole() {
        #expect(RoleInLabelRule.stripRole(from: "Отправить кнопка", word: "кнопка") == "Отправить")
        #expect(RoleInLabelRule.stripRole(from: "Send button", word: "button") == "Send")
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

@Suite("Значение без назначения")
struct ValueWithoutNameRuleTests {

    @Test("слайдер без подписи, но со значением — находка")
    func flagsSliderWithValueOnly() {
        let u = Utterance(index: 0, spoken: "50 %, slider", label: nil, value: "50 %", traits: ["slider"])
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("поле с отформатированным значением — находка")
    func flagsFormattedField() {
        let u = Utterance(index: 0, spoken: "2 015,00 RUB, textField", label: nil,
                          value: "2 015,00 RUB", traits: ["textField"])
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("подсказка играет роль имени — не находка")
    func ignoresPlaceholder() {
        // «Введите адрес» объясняет назначение, а не сообщает содержимое.
        let u = Utterance(index: 0, spoken: "Введите адрес, textField", label: nil,
                          value: "москва", traits: ["textField"], placeholder: "Введите адрес")
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("подпись есть — не находка")
    func ignoresLabelled() {
        let u = Utterance(index: 0, spoken: "Громкость, 50 %, slider", label: "Громкость",
                          value: "50 %", traits: ["slider"])
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("молчащий элемент оставляем блокеру, а не этому правилу")
    func silentGoesToEmptyRule() {
        // Границу между двумя правилами проверяем с обеих сторон: молчащий
        // элемент должен попасть в empty-utterance и НЕ попасть сюда.
        let u = Utterance(index: 0, spoken: "textField", label: nil, traits: ["textField"])
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) == nil)
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("говорящий элемент оставляем этому правилу, а не блокеру")
    func speakingIsNotBlocker() {
        // Обратная сторона той же границы: регрессионный тест на находку
        // из Eureka, где блокер обвинял слайдер, произносящий «50 %».
        let u = Utterance(index: 0, spoken: "50 %, slider", label: nil, value: "50 %", traits: ["slider"])
        #expect(EmptyUtteranceRule().evaluate(u, in: context(screen([u]))) == nil)
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) != nil)
    }

    @Test("неинтерактивный текст со значением — не находка")
    func ignoresStaticText() {
        let u = Utterance(index: 0, spoken: "None", label: nil, value: "None", traits: [])
        #expect(ValueWithoutNameRule().evaluate(u, in: context(screen([u]))) == nil)
    }
}

@Suite("Общая подпись только у нажимаемого")
struct GenericLabelInteractivityTests {

    @Test("статический текст «None» находкой не считается")
    func ignoresNonInteractiveNone() {
        // Регрессионный тест из Eureka: правило спрашивает «понятно ли, что
        // произойдёт при нажатии», а нажимать было нечего — признаков нет.
        let u = Utterance(index: 0, spoken: "None", label: "None", traits: [])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u]))) == nil)
    }

    @Test("кнопка с той же подписью находкой остаётся")
    func flagsInteractiveNone() {
        let u = Utterance(index: 0, spoken: "None, button", label: "None", traits: ["button"])
        #expect(GenericLabelRule().evaluate(u, in: context(screen([u]))) != nil)
    }
}

@Suite("Непереведённая подпись — только на локализованном экране")
struct UntranslatedLabelLocalizationTests {

    /// Экран из русских подписей плюс одна английская — настоящая утечка.
    private func localizedScreen(leak: String) -> ScreenSnapshot {
        var us = (0..<8).map {
            Utterance(index: $0, spoken: "Кнопка \($0), button", label: "Кнопка \($0)", traits: ["button"])
        }
        us.append(Utterance(index: 8, spoken: "\(leak), button", label: leak, traits: ["button"]))
        return screen(us)
    }

    /// Экран целиком на английском — приложение просто работает на английском.
    private func englishScreen(_ label: String) -> ScreenSnapshot {
        var us = (0..<8).map {
            Utterance(index: $0, spoken: "Item \($0), button", label: "Item\($0)", traits: ["button"])
        }
        us.append(Utterance(index: 8, spoken: "\(label), button", label: label, traits: ["button"]))
        return screen(us)
    }

    @Test("английское слово среди русских подписей — находка")
    func flagsLeakInLocalizedScreen() {
        let s = localizedScreen(leak: "Favorites")
        let u = s.utterances.last!
        #expect(UntranslatedLabelRule().evaluate(u, in: context(s, locale: "ru")) != nil)
    }

    @Test("экран целиком на английском — не находка")
    func ignoresFullyEnglishScreen() {
        // Регрессионный тест из Fitness и «Новостей»: кириллицы на экране ноль
        // процентов, приложение работает на английском, а правило обвиняло
        // в непереводе каждое слово подряд — «Close», «Summary», «Done».
        let s = englishScreen("Summary")
        let u = s.utterances.last!
        #expect(UntranslatedLabelRule().evaluate(u, in: context(s, locale: "ru")) == nil)
    }

    @Test("экран с двумя подписями не судим — выборка ничего не значит")
    func ignoresTinyScreen() {
        let us = [
            Utterance(index: 0, spoken: "Готово, button", label: "Готово", traits: ["button"]),
            Utterance(index: 1, spoken: "Cancel, button", label: "Cancel", traits: ["button"]),
        ]
        let s = screen(us)
        #expect(UntranslatedLabelRule().evaluate(us[1], in: context(s, locale: "ru")) == nil)
    }

    @Test("доля родной письменности считается по подписям экрана")
    func measuresLocalizedShare() {
        #expect(UntranslatedLabelRule().isLocalized(localizedScreen(leak: "Favorites")) == true)
        #expect(UntranslatedLabelRule().isLocalized(englishScreen("Summary")) == false)
    }
}
