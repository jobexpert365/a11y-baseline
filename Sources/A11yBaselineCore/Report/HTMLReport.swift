import Foundation

/// Публичная страница о доступности одного приложения.
///
/// Это не отчёт для клиента, а страница индекса: её находят поиском, и найти
/// её должна в первую очередь сама команда приложения. Отсюда три правила
/// формулировок, которых нет в Markdown-отчёте.
///
/// **Только факты, никаких обвинений.** Страница говорит «в этой сборке
/// проверено то-то, найдено то-то», а не «приложение недоступно». Разница
/// не косметическая: первое воспроизводимо и проверяемо, второе — оценка,
/// за которую отвечать нечем.
///
/// **Границы проверки названы вслух.** На странице явно написано, что машина
/// проверяет, а что нет. Без этого страница читается как приговор, хотя
/// механическая проверка ловит меньшую часть проблем.
///
/// **Есть способ возразить.** Команда должна видеть, куда написать, если
/// проверка ошиблась. Это и защита, и канал: написавший — уже контакт.
public struct HTMLReport: Sendable {

    public struct Meta: Sendable {
        public var contactURL: String
        public var indexURL: String
        public var generatedOn: String

        public init(contactURL: String, indexURL: String, generatedOn: String) {
            self.contactURL = contactURL
            self.indexURL = indexURL
            self.generatedOn = generatedOn
        }
    }

    public init() {}

    public func render(baseline: Baseline, findings: [Finding], meta: Meta) -> String {
        let engine = findings.filter { $0.source == .ruleEngine }
        let platform = baseline.screens.flatMap(\.platformAuditFindings)
        let elementCount = baseline.screens.reduce(0) { $0 + $1.utterances.count }

        var rows: [String] = []
        for severity in [Severity.blocker, .serious, .moderate, .minor] {
            let group = engine.filter { $0.severity == severity }
            guard !group.isEmpty else { continue }
            rows.append("""
              <section class="group">
                <h2>\(severityTitle(severity)) <span class="count">\(group.count)</span></h2>
                \(group.map(renderFinding).joined(separator: "\n"))
              </section>
            """)
        }

        return """
        <!doctype html>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Доступность \(escape(baseline.app)) — проверка VoiceOver</title>
        <meta name="description" content="Что VoiceOver произносит в приложении \(escape(baseline.app)): результат автоматической проверки \(elementCount) элементов интерфейса.">
        <style>\(css)</style>
        </head>
        <body>
        <main>
          <header>
            <p class="eyebrow"><a href="\(escape(meta.indexURL))">Индекс доступности</a> · проверено \(escape(meta.generatedOn))</p>
            <h1>\(escape(baseline.app))</h1>
            <p class="lede">
              Автоматическая проверка того, что произносит VoiceOver.
              Версия \(escape(baseline.appVersion)), iOS \(escape(baseline.osVersion)),
              язык интерфейса «\(escape(baseline.locale))». Пройдено элементов: \(elementCount).
            </p>
            <dl class="tally">
              <div><dt>Находки проверок</dt><dd>\(engine.count)</dd></div>
              <div><dt>Встроенный аудит Apple</dt><dd>\(platform.count)</dd></div>
              <div><dt>Экранов</dt><dd>\(baseline.screens.count)</dd></div>
            </dl>
          </header>

          <section class="scope">
            <h2>Что проверено, а что нет</h2>
            <p>
              Машина проверяет форму: есть ли подпись, не попало ли в неё имя файла,
              не звучат ли элементы одинаково, совпадает ли видимая надпись с озвучкой.
              Всё это воспроизводимо — прогон можно повторить и получить тот же результат.
            </p>
            <p>
              Машина <strong>не проверяет смысл</strong>. Подпись «Кнопка 2» пройдёт все
              проверки, потому что формально она есть. Осмысленность формулировок,
              логику озвучивания изменений и реальный сценарий работы с VoiceOver
              оценивает только человек, и эта страница таких выводов не делает.
            </p>
          </section>

          \(rows.joined(separator: "\n"))

          \(platform.isEmpty ? "" : """
          <section class="group platform">
            <h2>Что нашли встроенные инструменты Apple <span class="count">\(platform.count)</span></h2>
            <p class="note">
              Эти находки выдаёт <code>performAccessibilityAudit</code> — он входит
              в Xcode и доступен любой команде бесплатно. Раздел показан отдельно,
              чтобы было видно, где заканчивается бесплатное.
            </p>
            <ul>\(platform.map { "<li>\(escape($0.summary))</li>" }.joined())</ul>
          </section>
          """)

          <footer>
            <h2>Проверка ошиблась?</h2>
            <p>
              Ложное срабатывание — это дефект инструмента, а не спор о вкусах.
              Напишите, и страница будет исправлена: <a href="\(escape(meta.contactURL))">сообщить об ошибке</a>.
            </p>
            <p class="repro">
              Проверка выполнена открытым инструментом, результат воспроизводим:
              <a href="https://github.com/jobexpert365/a11y-baseline">a11y-baseline</a>.
            </p>
          </footer>
        </main>
        </body>
        </html>
        """
    }

    private func renderFinding(_ finding: Finding) -> String {
        let standard = finding.standard.map { s in
            let wcag = s.wcag22.map { " · WCAG \($0)" } ?? ""
            return "<p class=\"std\">EN 301 549 п. \(escape(s.en301549))\(wcag) — \(escape(s.title))</p>"
        } ?? ""

        return """
        <article class="finding">
          <h3>\(escape(finding.summary))</h3>
          <p class="screen">\(escape(finding.screen))</p>
          <p>\(escape(finding.evidence))</p>
          \(standard)
        </article>
        """
    }

    private func severityTitle(_ severity: Severity) -> String {
        switch severity {
        case .blocker: "Задача невыполнима"
        case .serious: "Непонятно, что делает элемент"
        case .moderate: "Понятно с усилием"
        case .minor: "Мелочи"
        }
    }

    /// Экранирование обязательно: в подписи элемента может оказаться что угодно,
    /// включая угловые скобки и кавычки из чужого кода.
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Стили встроены в страницу намеренно: страница индекса должна открываться
    /// одним файлом, без сборки и без внешних запросов.
    private var css: String {
        """
        :root {
          --ground: #f6f7f9; --surface: #fff; --ink: #14181f; --ink-2: #444c5a;
          --muted: #6b7280; --hair: #e2e5ea; --accent: #8a3324; --ok: #1a6b5f;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --ground: #0f1216; --surface: #171b21; --ink: #e8eaee; --ink-2: #c3c8d0;
            --muted: #8b919b; --hair: #262b33; --accent: #e08a76; --ok: #5ab5a4;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0; background: var(--ground); color: var(--ink);
          font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
        }
        main { max-width: 720px; margin: 0 auto; padding: 40px 20px 80px; }
        .eyebrow { font-size: 13px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); margin: 0 0 12px; }
        .eyebrow a { color: var(--muted); }
        h1 { font-size: clamp(30px, 6vw, 42px); line-height: 1.1; margin: 0 0 14px; }
        h2 { font-size: 20px; margin: 36px 0 12px; }
        h3 { font-size: 17px; margin: 0 0 6px; }
        .lede { color: var(--ink-2); margin: 0 0 22px; }
        .tally { display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 8px; padding: 0; }
        .tally div { background: var(--surface); border: 1px solid var(--hair); border-radius: 6px; padding: 10px 14px; }
        .tally dt { font-size: 12px; color: var(--muted); margin: 0; }
        .tally dd { margin: 2px 0 0; font-size: 22px; font-variant-numeric: tabular-nums; }
        .scope { border-left: 3px solid var(--ok); padding: 4px 0 4px 16px; margin: 32px 0; color: var(--ink-2); }
        .scope h2 { margin-top: 0; }
        .count { font-size: 14px; color: var(--muted); font-variant-numeric: tabular-nums; }
        .finding { background: var(--surface); border: 1px solid var(--hair); border-left: 3px solid var(--accent); border-radius: 6px; padding: 16px 18px; margin: 0 0 10px; }
        .finding .screen { font-size: 13px; color: var(--muted); margin: 0 0 8px; }
        .finding p { margin: 0 0 8px; color: var(--ink-2); }
        .std { font-size: 13px; color: var(--muted); margin: 0; }
        .platform ul { padding-left: 20px; color: var(--ink-2); }
        .platform .note { color: var(--muted); font-size: 14px; }
        footer { margin-top: 48px; border-top: 1px solid var(--hair); padding-top: 20px; color: var(--ink-2); }
        .repro { font-size: 14px; color: var(--muted); }
        a { color: var(--accent); }
        code { background: var(--ground); padding: 1px 5px; border-radius: 4px; font-size: .9em; }
        """
    }
}
