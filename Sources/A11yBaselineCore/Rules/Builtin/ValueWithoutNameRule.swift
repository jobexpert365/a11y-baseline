import Foundation

/// Элемент произносит своё значение, но не своё назначение.
///
/// Типичный носитель — поле ввода или слайдер внутри строки формы. Заголовок
/// строки нарисован рядом, но с самим элементом программно не связан, поэтому
/// при перемещении по элементам человек слышит «2 015,00 RUB, textField»
/// или «50 %, slider» и не знает, чем именно управляет.
///
/// От `empty-utterance` отличается принципиально: там элемент молчит, здесь
/// говорит. Поэтому и severity ниже блокера — человек всё же получает
/// обратную связь и может дойти до смысла по соседнему тексту. Разделены
/// эти два случая после прогона по чужому коду: одно правило называло
/// «элементом без подписи» слайдер, который отчётливо произносит «50 %».
///
/// ПОДТВЕРЖДЕНИЕ ДАННЫМИ. Замер по 25 приложениям: 45 срабатываний, и все
/// в двух — Charts (32) и Eureka (13), то есть в приложениях, построенных
/// на формах и регуляторах. В 22 приложениях Apple — НОЛЬ. Это и есть
/// проверка на шум: правило, склонное к ложным находкам, сыпалось бы прежде
/// всего на самом большом и разнообразном корпусе, а не обходило его стороной.
public struct ValueWithoutNameRule: Rule {

    public static let id = "value-without-name"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance) else { return nil }

        // Подпись есть — судить нечего.
        let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard label.isEmpty else { return nil }

        // Подсказка играет роль имени: «Введите адрес» объясняет назначение,
        // а не сообщает текущее содержимое. Такой элемент под правило
        // не подпадает.
        let placeholder = utterance.placeholder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard placeholder.isEmpty else { return nil }

        // Должно быть что произносить: иначе это молчащий элемент,
        // а он тяжелее и им занимается EmptyUtteranceRule.
        let value = utterance.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let visible = utterance.visibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let spokenPart = value.isEmpty ? visible : value
        guard !spokenPart.isEmpty else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            // Значение в заголовок НЕ выносим — оно уходит в доказательство.
            //
            // Схлопывание группирует находки по правилу, экрану и заголовку,
            // поэтому заголовок с подставленным значением делает каждую
            // находку уникальной. На Charts это дало 24 отдельные записи
            // вместо одного дефекта «регуляторы графика не подписаны»,
            // повторённого 24 раза. Читать такой отчёт невозможно, а дефект
            // там один.
            summary: "Элемент произносит только значение, без назначения",
            evidence: "VoiceOver произносит: «\(utterance.spoken)». Значение слышно, а чем управляет элемент — нет.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "TextField(\"\", value: $amount, format: .currency(code: \"RUB\"))",
                after: "TextField(\"\", value: $amount, format: .currency(code: \"RUB\"))\n    .accessibilityLabel(\"Сумма\")",
                note: "Заголовок строки, нарисованный рядом, для VoiceOver не существует: связь задаётся подписью, а не расположением."
            )
        )
    }
}
