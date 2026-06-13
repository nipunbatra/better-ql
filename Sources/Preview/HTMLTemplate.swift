import Foundation

/// Anchor for locating the extension bundle without coupling to the view controller
/// (so the renderers can be compiled into a unit-test target on their own).
private final class BundleAnchor {}

enum HTMLTemplate {
    /// Reads a bundled text resource (e.g. marked.min.js). Looks in the extension
    /// bundle first; falls back to BQL_RESOURCE_DIR so the renderer can be exercised
    /// by an offscreen test harness outside the .appex.
    static func resource(_ name: String, _ ext: String) -> String {
        let bundle = Bundle(for: BundleAnchor.self)
        if let url = bundle.url(forResource: name, withExtension: ext),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        if let dir = ProcessInfo.processInfo.environment["BQL_RESOURCE_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).\(ext)")
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return ""
    }

    /// Wraps body HTML in a full document with shared, dark-mode-aware styling.
    static func page(title: String, body: String, headExtra: String = "") -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>\(baseCSS)</style>
        \(headExtra)
        </head>
        <body>
        <div class="bql-wrap">
        \(body)
        </div>
        </body>
        </html>
        """
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A graceful, copyable error page — shown instead of a dead end so the user
    /// can grab the details to report.
    static func errorPage(title: String, summary: String, details: String) -> String {
        let body = """
        <div class="bql-err">
          <div class="bql-err-badge">⚠️ Couldn't preview this file</div>
          <p class="bql-sub">\(escapeHTML(summary))</p>
          <pre id="bql-d">\(escapeHTML(details))</pre>
          <button id="bql-copy" onclick="bqlCopy()">Copy details</button>
          <span id="bql-ok">Copied ✓</span>
        </div>
        <script>
          function bqlCopy(){
            var t = document.getElementById('bql-d').textContent;
            var ta = document.createElement('textarea');
            ta.value = t; document.body.appendChild(ta); ta.select();
            try { document.execCommand('copy'); } catch(e) {}
            document.body.removeChild(ta);
            document.getElementById('bql-ok').style.opacity = '1';
          }
        </script>
        """
        return page(title: title, body: body)
    }

    static let baseCSS = """
    :root {
      --fg: #1f2328; --bg: #ffffff; --muted: #59636e; --border: #d1d9e0;
      --accent: #0969da; --code-bg: #f6f8fa; --row: #f6f8fa; --hover: #eef1f4;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #e6edf3; --bg: #0d1117; --muted: #9198a1; --border: #2a313c;
        --accent: #4493f8; --code-bg: #161b22; --row: #161b22; --hover: #1c2230;
      }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg);
      font: 14px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased; }
    .bql-wrap { max-width: 920px; margin: 0 auto; padding: 28px 32px 48px; }
    h1,h2,h3,h4 { line-height: 1.25; margin: 1.4em 0 .5em; font-weight: 600; }
    h1 { font-size: 1.9em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
    h2 { font-size: 1.45em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
    h3 { font-size: 1.2em; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    p, ul, ol, blockquote, table, pre { margin: 0 0 1em; }
    ul, ol { padding-left: 1.6em; }
    blockquote { border-left: 3px solid var(--border); padding: 0 1em; color: var(--muted); }
    code { font: 12.5px/1.5 "SF Mono", ui-monospace, Menlo, monospace;
      background: var(--code-bg); padding: .15em .4em; border-radius: 5px; }
    pre { background: var(--code-bg); padding: 14px 16px; border-radius: 8px; overflow: auto;
      border: 1px solid var(--border); }
    pre code { background: none; padding: 0; }
    img { max-width: 100%; }
    hr { border: none; border-top: 1px solid var(--border); margin: 1.6em 0; }
    table { border-collapse: collapse; width: 100%; font-size: 13px; }
    th, td { border: 1px solid var(--border); padding: 6px 12px; text-align: left; }
    thead th { background: var(--row); }

    /* Listing (folders / archives) */
    .bql-head { display: flex; align-items: baseline; gap: 10px; margin-bottom: 4px; }
    .bql-head h1 { border: none; margin: 0; font-size: 1.4em; padding: 0; }
    .bql-sub { color: var(--muted); font-size: 13px; margin: 0 0 18px; }
    table.bql-list { border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
    table.bql-list th { background: var(--row); font-weight: 600; color: var(--muted);
      font-size: 12px; text-transform: uppercase; letter-spacing: .03em; }
    table.bql-list td, table.bql-list th { border: none; border-bottom: 1px solid var(--border);
      padding: 7px 14px; white-space: nowrap; }
    table.bql-list tr:last-child td { border-bottom: none; }
    table.bql-list tr:hover td { background: var(--hover); }
    td.name { width: 100%; white-space: normal; }
    td.kind { color: var(--muted); }
    td.size, td.date { color: var(--muted); text-align: right; font-variant-numeric: tabular-nums; }
    th.kind { text-align: left; }
    .ic { display: inline-block; width: 1.3em; }
    .dir .name { font-weight: 600; }
    img.thumb { width: 20px; height: 20px; object-fit: cover; border-radius: 3px;
      vertical-align: -5px; border: 1px solid var(--border); background: var(--code-bg); }

    /* CSV / TSV tables */
    .bql-scroll { overflow: auto; border: 1px solid var(--border); border-radius: 8px; }
    table.bql-csv { border-collapse: collapse; width: 100%; font-size: 12.5px; margin: 0; }
    table.bql-csv th, table.bql-csv td { border-bottom: 1px solid var(--border);
      border-right: 1px solid var(--border); padding: 5px 10px; text-align: left;
      white-space: nowrap; max-width: 360px; overflow: hidden; text-overflow: ellipsis; }
    table.bql-csv thead th { position: sticky; top: 0; background: var(--row);
      font-weight: 600; z-index: 1; }
    table.bql-csv td.rownum, table.bql-csv th.rownum { color: var(--muted);
      text-align: right; background: var(--bg); position: sticky; left: 0;
      font-variant-numeric: tabular-nums; }
    table.bql-csv tr:hover td { background: var(--hover); }

    /* Error page */
    .bql-err { max-width: 640px; }
    .bql-err-badge { font-size: 1.2em; font-weight: 600; margin-bottom: 6px; }
    .bql-err pre { white-space: pre-wrap; word-break: break-word; }
    #bql-copy { font: 13px -apple-system, sans-serif; padding: 6px 14px; border-radius: 7px;
      border: 1px solid var(--border); background: var(--row); color: var(--fg); cursor: pointer; }
    #bql-copy:hover { background: var(--hover); }
    #bql-ok { margin-left: 10px; color: var(--muted); opacity: 0; transition: opacity .15s; }
    """
}
