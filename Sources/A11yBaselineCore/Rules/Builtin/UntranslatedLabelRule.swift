import Foundation

/// Подпись на чужом языке в локализованном интерфейсе.
///
/// Ловит два случая сразу: строку, до которой не дошёл перевод, и подпись,
/// которую система вывела из английского имени символа. Для человека это одно
/// и то же — посреди русской речи VoiceOver произносит английское слово.
///
/// ВАЖНОЕ ОГРАНИЧЕНИЕ ОБЛАСТИ. Правило работает только там, где язык
/// интерфейса отличается от латиницы по письменности: русский, украинский,
/// греческий, иврит, японский. Для немецкого или французского непереведённое
/// английское слово неотличимо от переведённого по одному лишь виду строки,
/// и правило честно молчит, а не гадает.
public struct UntranslatedLabelRule: Rule {

    public static let id = "untranslated-label"
    public static let standard = Standards.nameRoleValue

    /// Сколько подписей экрана должно быть на родной письменности, чтобы
    /// считать экран локализованным.
    private static let localizedThreshold = 0.5

    /// Меньше этого числа подписей — судить не о чем, выборка ничего не значит.
    private static let minimumLabels = 5

    public init() {}

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard !context.locale.hasPrefix("en") else { return nil }
        guard context.isInteractive(utterance) else { return nil }
        guard utterance.visibleText == nil else { return nil }

        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              label.count >= 4,
              !label.contains(" "),
              label.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }

        // Экран должен быть ДОКАЗАННО локализован.
        //
        // Правило берёт язык из манифеста, а манифест — это заявление о том,
        // на каком языке приложение ДОЛЖНО говорить, а не на каком оно говорит
        // на самом деле. Замер по индексу показал цену этой подмены: в Fitness
        // и «Новостях» кириллицы на экране НОЛЬ процентов — приложения целиком
        // работают на английском, — и правило обвиняло в непереводе каждое
        // английское слово подряд: «Close», «Summary», «Workout», «Done».
        // Шесть ложных находок из одиннадцати.
        //
        // Настоящая утечка перевода выглядит иначе: она меньшинство среди
        // переведённого. В «Фото» кириллицы 86%, и на этом фоне «Favorites»
        // и «Screenshots» — действительно непереведённые остатки.
        guard isLocalized(context.screen) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .minor,
            screen: context.screen.screen,
            summary: "Проверьте подпись «\(label)»: это название или непереведённый текст?",
            evidence: "VoiceOver произносит «\(utterance.spoken)» в приложении на языке «\(context.locale)». Если это бренд — всё в порядке. Если подпись подставилась автоматически из имени символа или не переведена — человек услышит слово на чужом языке.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: ".accessibilityLabel(\"\(label)\")",
                after: ".accessibilityLabel(NSLocalizedString(\"<ключ>\", comment: \"\"))",
                note: "Названия брендов не переводятся — если это оно, находку можно принять как исключение."
            )
        )
    }

    /// Экран считается локализованным, если больше половины его подписей
    /// написаны не латиницей.
    func isLocalized(_ screen: ScreenSnapshot) -> Bool {
        let labels = screen.utterances
            .compactMap { $0.label?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard labels.count >= Self.minimumLabels else { return false }

        let native = labels.filter { label in
            label.contains { $0.isLetter && !$0.isASCII }
        }
        return Double(native.count) / Double(labels.count) >= Self.localizedThreshold
    }
}
