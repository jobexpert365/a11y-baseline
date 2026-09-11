import Foundation

/// В подпись утекло имя ресурса.
///
/// Возникает, когда `Image("ic_close_24")` попадает в дерево доступности без
/// явной подписи: система берёт имя ассета. Встроенный аудит это пропускает,
/// потому что описание формально непустое.
public struct FilenameLabelRule: Rule {

    public static let id = "filename-label"
    public static let standard = Standards.nonTextContent

    public init() {}

    /// Признаки имени файла или ассета, а не человеческой фразы.
    private func looksLikeAssetName(_ label: String) -> Bool {
        let lower = label.lowercased()

        // Имя ресурса из проекта не содержит пробелов и косых черт.
        // Найдено прогоном по Pulse: подпись «GET /octocat.png» —
        // это строка HTTP-запроса, которую логгер показывает по делу,
        // а правило видело только расширение на конце и сообщало о дефекте.
        guard !label.contains(" "), !label.contains("/") else { return false }

        // Адрес сервера — это содержимое, а не утёкшее имя ассета.
        // Проверка общая с правилом имени символа: одна строка, одно суждение.
        guard !TechnicalText.looksLikeDomain(label) else { return false }

        // Расширение файла.
        for ext in [".png", ".jpg", ".jpeg", ".pdf", ".svg", ".webp", ".heic"] where lower.hasSuffix(ext) {
            return true
        }

        // Типовые префиксы иконок.
        for prefix in ["ic_", "img_", "icon_", "asset_", "btn_", "bg_"] where lower.hasPrefix(prefix) {
            return true
        }

        // Нет пробелов, но есть служебные разделители или CamelCase-склейка,
        // и при этом строка достаточно длинная, чтобы не быть аббревиатурой.
        let hasSpace = label.contains(" ")
        let hasSeparator = label.contains("_") || label.contains("-")
        if !hasSpace && hasSeparator && label.count >= 6 { return true }

        // IMG_2043 и подобное: буквы, подчёркивание, цифры.
        if !hasSpace, label.range(of: #"^[A-Za-z]{2,5}[_-]?\d{3,}$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    public func evaluate(_ utterance: Utterance, in context: RuleContext) -> Finding? {
        guard let label = utterance.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              looksLikeAssetName(label) else { return nil }

        return Finding(
            key: makeKey(screen: context.screen.screen, utterance: utterance),
            ruleID: Self.id,
            source: .ruleEngine,
            severity: .serious,
            screen: context.screen.screen,
            summary: "В подпись попало имя ресурса: «\(label)»",
            evidence: "VoiceOver произносит: «\(utterance.spoken)». Это имя файла из проекта, а не описание для человека.",
            standard: Self.standard,
            utteranceIndex: utterance.index,
            fix: Finding.Fix(
                before: "Image(\"\(label)\")",
                after: "Image(\"\(label)\")\n    .accessibilityLabel(\"<назначение элемента>\")",
                note: "Если картинка декоративная — уберите её из дерева целиком: .accessibilityHidden(true)."
            )
        )
    }
}
