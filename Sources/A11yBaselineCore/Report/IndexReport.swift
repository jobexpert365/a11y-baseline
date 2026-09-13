import Foundation

/// Главная страница индекса: список проверенных приложений.
///
/// Роль у неё двойная и обе важны. Для человека это оглавление. Для поиска —
/// единственная страница, которая связывает отдельные отчёты в набор
/// и объясняет, по какому методу они получены: страница про одно приложение
/// без такого контекста читается как случайная претензия.
public struct IndexReport: Sendable {

    /// Строка индекса. Сознательно не содержит вердикта вроде «доступно»
    /// или «недоступно»: машина проверяет форму, а не пригодность
    /// приложения для человека, и притворяться иначе нельзя.
    public struct Entry: Sendable {
        public var app: String
        public var slug: String
        public var elements: Int
        public var findings: Int
        public var blockers: Int

        public init(app: String, slug: String, elements: Int, findings: Int, blockers: Int) {
            self.app = app
            self.slug = slug
            self.elements = elements
            self.findings = findings
            self.blockers = blockers
        }
    }

    public init() {}

    public func render(entries: [Entry], generatedOn: String) -> String {
        // Сортировка по числу находок убывающе — но это НЕ рейтинг «кто хуже».
        // Приложение с двумя сотнями элементов и сорока находками устроено
        // иначе, чем с двадцатью элементами и одной. Порядок нужен только
        // чтобы страница читалась сверху вниз.
        let rows = entries.sorted { $0.findings > $1.findings }.map { entry in
            // Приложение, в котором не пройдено ни одного элемента, помечается
            // отдельно и НЕ показывается как «ноль находок».
            //
            // Это вопрос честности, а не оформления. Ноль элементов означает,
            // что сканер не смог войти в приложение — оно не запустилось,
            // показало экран входа или системный запрос. Вывести такую строку
            // рядом с настоящими нулями значит выдать «мы ничего не проверили»
            // за «мы проверили и всё чисто». Ровно на такой подмене и теряют
            // доверие к отчёту.
            guard entry.elements > 0 else {
                return """
                <tr class="skipped">
                  <td>\(escape(entry.app))</td>
                  <td class="num">—</td>
                  <td colspan="2">не удалось пройти</td>
                </tr>
                """
            }
            return """
            <tr>
              <td><a href="apps/\(entry.slug)/">\(escape(entry.app))</a></td>
              <td class="num">\(entry.elements)</td>
              <td class="num">\(entry.findings)</td>
              <td class="num">\(entry.blockers > 0 ? String(entry.blockers) : "—")</td>
            </tr>
            """
        }.joined(separator: "\n")

        let walked = entries.filter { $0.elements > 0 }
        let clean = walked.filter { $0.findings == 0 }.count

        return """
        <!doctype html>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Индекс доступности iOS-приложений</title>
        <meta name="description" content="Что произносит VoiceOver в \(entries.count) приложениях: результаты автоматической проверки открытым инструментом.">
        <style>\(css)</style>
        </head>
        <body>
        <main>
          <header>
            <p class="eyebrow">обновлено \(escape(generatedOn))</p>
            <h1>Индекс доступности iOS-приложений</h1>
            <p class="lede">
              Что произносит VoiceOver в реальных приложениях. Каждая страница —
              результат прогона открытого инструмента, который можно повторить
              и получить тот же результат.
            </p>
          </header>

          <section class="method">
            <h2>Как читать эти страницы</h2>
            <p>
              Это не рейтинг и не оценка приложений. Машина проверяет форму:
              есть ли у элемента подпись, не попало ли в неё имя файла или
              идентификатор иконки, не звучат ли несколько элементов одинаково.
            </p>
            <p>
              Машина <strong>не проверяет смысл</strong> и не может сказать,
              удобно ли приложением пользоваться незрячему человеку. Подпись
              «Кнопка 2» пройдёт все проверки. Ноль находок означает только,
              что механических дефектов не найдено на пройденных экранах.
            </p>
            <p>
              Обход автоматический и поверхностный: стартовый экран и переход
              вглубь. Это малая часть приложения, и число элементов в таблице
              показывает ровно то, что было пройдено.
            </p>
          </section>

          <div class="scroll">
          <table>
            <thead><tr><th>Приложение</th><th class="num">Элементов</th><th class="num">Находок</th><th class="num">Блокеров</th></tr></thead>
            <tbody>
            \(rows)
            </tbody>
          </table>
          </div>

          <p class="tally">Без находок: \(clean) из \(walked.count) пройденных.\(entries.count > walked.count ? " Не удалось пройти: \(entries.count - walked.count)." : "")</p>

          <footer>
            <p>
              Проверка ошиблась? Это дефект инструмента, а не спор о вкусах —
              <a href="https://github.com/jobexpert365/a11y-baseline/issues/new">сообщите</a>,
              и страница будет исправлена.
            </p>
            <p class="repro">
              Инструмент открыт, прогон можно повторить:
              <a href="https://github.com/jobexpert365/a11y-baseline">a11y-baseline</a>.
            </p>
          </footer>
        </main>
        </body>
        </html>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

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
        body { margin: 0; background: var(--ground); color: var(--ink);
          font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
        main { max-width: 760px; margin: 0 auto; padding: 40px 20px 80px; }
        .eyebrow { font-size: 13px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); margin: 0 0 12px; }
        h1 { font-size: clamp(30px, 6vw, 42px); line-height: 1.1; margin: 0 0 14px; }
        h2 { font-size: 20px; margin: 32px 0 12px; }
        .lede { color: var(--ink-2); margin: 0 0 22px; }
        .method { border-left: 3px solid var(--ok); padding: 4px 0 4px 16px; margin: 28px 0; color: var(--ink-2); }
        .method h2 { margin-top: 0; }
        .scroll { overflow-x: auto; border: 1px solid var(--hair); border-radius: 6px; margin: 24px 0 12px; }
        table { border-collapse: collapse; width: 100%; background: var(--surface); min-width: 460px; }
        th, td { text-align: left; padding: 11px 14px; border-bottom: 1px solid var(--hair); }
        thead th { font-size: 12px; letter-spacing: .05em; text-transform: uppercase; color: var(--muted); background: var(--ground); }
        tbody tr:last-child td { border-bottom: 0; }
        .num { text-align: right; font-variant-numeric: tabular-nums; }
        .tally { color: var(--muted); font-size: 14px; }
        .skipped td { color: var(--muted); font-style: italic; }
        footer { margin-top: 40px; border-top: 1px solid var(--hair); padding-top: 20px; color: var(--ink-2); }
        .repro { font-size: 14px; color: var(--muted); }
        a { color: var(--accent); }
        """
    }
}
