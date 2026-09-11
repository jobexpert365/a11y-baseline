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

/// Транслитерация имени приложения в адрес страницы.
///
/// Адреса должны быть латиницей и без пробелов: они попадают в ссылки,
/// в поисковую выдачу и в файловую систему. Русские названия приложений
/// при этом никуда не деваются — они остаются в заголовке страницы.
func slugify(_ name: String) -> String {
    let map: [Character: String] = [
        "а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z",
        "и":"i","й":"y","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r",
        "с":"s","т":"t","у":"u","ф":"f","х":"h","ц":"c","ч":"ch","ш":"sh","щ":"sch",
        "ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya",
    ]
    var out = ""
    for character in name.lowercased() {
        if let replacement = map[character] { out += replacement }
        else if character.isLetter || character.isNumber { out.append(character) }
        else if !out.hasSuffix("-") { out.append("-") }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// Собирает сайт индекса из каталога с базовыми линиями.
func buildIndex(from inputDir: URL, to outputDir: URL) {
    let fm = FileManager.default
    let store = BaselineStore()

    guard let files = try? fm.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) else {
        fail("не удалось прочитать каталог \(inputDir.path)")
    }
    guard !files.isEmpty else { fail("в каталоге \(inputDir.path) нет базовых линий") }

    let generatedOn = ProcessInfo.processInfo.environment["A11Y_REPORT_DATE"] ?? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: Date())
    }()

    var entries: [IndexReport.Entry] = []
    for file in files {
        guard let baseline = try? store.read(from: file) else {
            print("пропущено (не читается): \(file.lastPathComponent)")
            continue
        }
        let findings = RuleRegistry.runMatching(baseline)
        let slug = slugify(baseline.app)
        let elements = baseline.screens.reduce(0) { $0 + $1.utterances.count }

        // Для непройденного приложения страница не создаётся: публиковать
        // отчёт «проверено 0 элементов, найдено 0 дефектов» — значит выдавать
        // неудачу сканера за чистый результат.
        guard elements > 0 else {
            entries.append(IndexReport.Entry(app: baseline.app, slug: slug, elements: 0, findings: 0, blockers: 0))
            print("пропущено (не пройдено ни одного элемента): \(baseline.app)")
            continue
        }

        let appDir = outputDir.appendingPathComponent("apps/\(slug)")
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)

        let meta = HTMLReport.Meta(
            contactURL: "https://github.com/jobexpert365/a11y-baseline/issues/new",
            indexURL: "../../",
            generatedOn: generatedOn
        )
        let html = HTMLReport().render(baseline: baseline, findings: findings, meta: meta)
        try? html.write(to: appDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        entries.append(IndexReport.Entry(
            app: baseline.app,
            slug: slug,
            elements: elements,
            findings: findings.count,
            blockers: findings.filter { $0.severity == .blocker }.count
        ))
        print("страница: apps/\(slug)/ — \(findings.count) находок")
    }

    try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let index = IndexReport().render(entries: entries, generatedOn: generatedOn)
    try? index.write(to: outputDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    print("индекс собран: \(entries.count) приложений в \(outputDir.path)")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Ошибка: \(message)\n".utf8))
    exit(1)
}

// Режим сборки индекса: на входе каталог с базовыми линиями, на выходе
// готовый сайт. Отдельный режим, а не флаг, потому что это другая работа:
// одиночный отчёт делают для клиента, индекс — для поиска.
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--index" {
    let inputDir = URL(fileURLWithPath: CommandLine.arguments[2])
    let outputDir = URL(fileURLWithPath: CommandLine.arguments[3])
    buildIndex(from: inputDir, to: outputDir)
    exit(0)
}

guard let args = Arguments.parse(CommandLine.arguments) else {
    fail("использование:\n  a11y-report <baseline.json> [--html out.html] [--markdown out.md]\n  a11y-report --index <каталог-с-базовыми-линиями> <каталог-сайта>")
}

let store = BaselineStore()
let baseline: Baseline
do {
    baseline = try store.read(from: URL(fileURLWithPath: args.baselinePath))
} catch {
    fail("не удалось прочитать базовую линию: \(error.localizedDescription)")
}

let findings = RuleRegistry.runMatching(baseline)

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
