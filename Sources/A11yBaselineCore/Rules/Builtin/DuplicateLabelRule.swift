import Foundation

/// Несколько интерактивных элементов на экране звучат одинаково.
///
/// Классический случай — список карточек, где у каждой кнопка «Подробнее».
/// Глазами их различают по окружению, на слух — нечем: человек слышит
/// «Подробнее, кнопка» шесть раз подряд и не знает, к чему относится каждая.
///
/// Правило принципиально не локальное: об одном элементе судить нельзя,
/// нужен весь экран. Это и есть причина, по которой правилу передаётся
/// контекст, а не только реплика.
///
/// Сравниваются РЕПЛИКИ ЦЕЛИКОМ, а не подписи. Разница выяснилась на живом
/// прогоне по «Настройкам» iOS: там есть строка списка «Поиск» и поле поиска
/// «Поиск». Подписи совпадают, но VoiceOver произносит «Поиск, кнопка»
/// и «Поиск, поле поиска» — роль он объявляет сам, и на слух эти элементы
/// различимы. Правило, сравнивавшее только подписи, сообщало о дефекте там,
/// где для слушающего человека его нет.
public struct DuplicateLabelRule: Rule {

    public static let id = "duplicate-label"
    public static let standard = Standards.nameRoleValue

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard context.isInteractive(utterance),
              let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }

        // Совпадать должна вся реплика: подпись плюс роль. Два элемента
        // с одинаковой подписью, но разными ролями человек различает на слух.
        let spoken = utterance.spoken.lowercased()
        let twins = context.screen.utterances.filter { other in
            other.index != utterance.index
                && context.isInteractive(other)
                && other.spoken.lowercased() == spoken
        }
        guard !twins.isEmpty else { return nil }

        // Считаем МЕСТА НА ЭКРАНЕ, а не узлы дерева.
        //
        // Правило спрашивает «может ли человек их спутать», а спутать можно
        // только то, что занимает разные места. Два узла с одинаковой рамкой —
        // это один и тот же элемент, попавший в дерево дважды (обычно
        // контейнер вместе со своим ребёнком), и человеку он достаётся один.
        //
        // Замер по 25 приложениям: из 18 групп дубликатов три оказались
        // целиком такими — «Закрыть» и «Загрузить» в Wallet, «Don't have
        // an Apple Account?» в Настройках. У всех трёх рамки совпадали
        // до сотых. И все три были у Apple, то есть попались по тому же
        // признаку, по которому в прошлый раз попалось правило о переводе:
        // срабатывание на самом вылизанном корпусе — повод проверить себя,
        // а не приложение.
        let group = ([utterance] + twins).sorted { $0.index < $1.index }
        var seenPlaces: Set<String> = []
        let distinct = group.filter { seenPlaces.insert(Self.placeKey(of: $0)).inserted }
        guard distinct.count >= 2 else { return nil }

        // Сообщаем один раз — на первом из группы. Иначе отчёт распухает
        // шестью одинаковыми находками там, где проблема одна.
        guard distinct.first?.index == utterance.index else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .moderate,
            screen: context.screen.screen,
            summary: "\(distinct.count) элемента звучат одинаково: «\(label)»",
            evidence: "Все они произносятся как «\(utterance.spoken)». На слух их невозможно различить, а глазами они различаются окружением.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Button(\"\(label)\") { open(item) }",
                after: "Button(\"\(label)\") { open(item) }\n    .accessibilityLabel(\"\(label): \\(item.title)\")",
                note: "Альтернатива без изменения подписи — объединить карточку в один элемент через .accessibilityElement(children: .combine)."
            )
        )
    }

    /// Ключ места на экране.
    ///
    /// Округляем до десятых: координаты приходят дробными из-за масштаба
    /// экрана, и два узла одного элемента отличаются на уровне машинного нуля,
    /// а не на уровне видимого положения.
    ///
    /// Элемент без рамки считается отдельным местом: без геометрии мы
    /// не вправе утверждать, что это тот же самый элемент, а молчать
    /// из-за отсутствия данных — значит пропускать настоящий дефект.
    private static func placeKey(of u: Utterance) -> String {
        guard let f = u.frame else { return "нет-рамки-\(u.index)" }
        func r(_ v: Double) -> String { String(format: "%.1f", v) }
        return "\(r(f.x)):\(r(f.y)):\(r(f.width)):\(r(f.height))"
    }
}
