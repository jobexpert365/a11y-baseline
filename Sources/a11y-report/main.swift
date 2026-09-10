import Foundation
import A11yBaselineCore

/// Утилита командной строки: базовая линия на входе, страница на выходе.
///
/// Отдельная цель, а не часть теста, потому что генерация страниц — это
/// конвейер: базовые линии снимаются на симуляторе, а страницы собираются
/// пачкой, в том числе на машине без Xcode.
///
/// Использование:
///   a11y-report <baseline.json> [--html out.html] [--markdown out.md]

struct Arguments {
    var baselinePath: String
    var htmlPath: String?
    var markdownPath: String?

    static func parse(_ argv: [String]) -> Arguments? {
        var rest = argv.dropFirst()
        guard let baseline = rest.first else { return nil }
        rest = rest.dropFirst()

        var html: String?
        var markdown: String?
        while let flag = rest.first {
            rest = rest.dropFirst()
            guard let value = rest.first else { return nil }
            rest = rest.dropFirst()
            switch flag {
            case "--html": html = value
            case "--markdown": markdown = value
            default: return nil
            }
        }
        return Arguments(baselinePath: baseline, htmlPath: html, markdownPath: markdown)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Ошибка: \(message)\n".utf8))
    exit(1)
}

guard let args = Arguments.parse(CommandLine.arguments) else {
    fail("использование: a11y-report <baseline.json> [--html out.html] [--markdown out.md]")
}

let store = BaselineStore()
let baseline: Baseline
do {
    baseline = try store.read(from: URL(fileURLWithPath: args.baselinePath))
} catch {
    fail("не удалось прочитать базовую линию: \(error.localizedDescription)")
}

let findings = RuleRegistry.standard.run(on: baseline)

// Дата берётся из окружения, если задана, иначе из системных часов.
// Переопределение нужно, чтобы страницы собирались воспроизводимо: одна
// и та же базовая линия должна давать байт в байт одинаковую страницу,
// иначе каждый пересбор индекса выглядит как изменение.
let generatedOn = ProcessInfo.processInfo.environment["A11Y_REPORT_DATE"] ?? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: Date())
}()

if let htmlPath = args.htmlPath {
    let meta = HTMLReport.Meta(
        contactURL: ProcessInfo.processInfo.environment["A11Y_CONTACT_URL"]
            ?? "https://github.com/jobexpert365/a11y-baseline/issues/new",
        indexURL: ProcessInfo.processInfo.environment["A11Y_INDEX_URL"] ?? "../index.html",
        generatedOn: generatedOn
    )
    let html = HTMLReport().render(baseline: baseline, findings: findings, meta: meta)
    do {
        try html.write(to: URL(fileURLWithPath: htmlPath), atomically: true, encoding: .utf8)
    } catch {
        fail("не удалось записать HTML: \(error.localizedDescription)")
    }
    print("HTML: \(htmlPath)")
}

if let markdownPath = args.markdownPath {
    let markdown = MarkdownReport().render(baseline: baseline, findings: findings)
    do {
        try markdown.write(to: URL(fileURLWithPath: markdownPath), atomically: true, encoding: .utf8)
    } catch {
        fail("не удалось записать Markdown: \(error.localizedDescription)")
    }
    print("Markdown: \(markdownPath)")
}

print("Приложение: \(baseline.app) \(baseline.appVersion)")
print("Находок: \(findings.count)")
for finding in findings {
    print("  \(finding.severity.rawValue)\t\(finding.ruleID)\t\(finding.summary)")
}
