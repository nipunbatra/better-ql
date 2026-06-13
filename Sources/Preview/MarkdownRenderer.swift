import Foundation

enum MarkdownRenderer {
    static func html(for url: URL) -> String {
        let raw = readText(url)

        // Embed the markdown as inert text inside a <script type="text/markdown">.
        // Only sequences that could close that element need neutralising.
        let safe = raw.replacingOccurrences(
            of: "</script", with: "<\\/script", options: .caseInsensitive)

        let marked = HTMLTemplate.resource("marked.min", "js")
        let hljs = HTMLTemplate.resource("highlight.min", "js")
        let hljsCSS = HTMLTemplate.resource("highlight-github", "css")

        let body = """
        <article id="content" class="markdown-body"></article>
        <script id="src" type="text/markdown">\(safe)</script>
        <script>\(marked)</script>
        <script>\(hljs)</script>
        <script>
          (function () {
            var raw = document.getElementById('src').textContent;
            if (window.marked) {
              marked.setOptions({ gfm: true, breaks: false, headerIds: true, mangle: false });
              document.getElementById('content').innerHTML = marked.parse(raw);
            } else {
              document.getElementById('content').textContent = raw;
            }
            if (window.hljs) {
              document.querySelectorAll('pre code').forEach(function (b) {
                try { hljs.highlightElement(b); } catch (e) {}
              });
            }
          })();
        </script>
        """

        let head = hljsCSS.isEmpty ? "" : """
        <style>\(hljsCSS)
        @media (prefers-color-scheme: dark) {
          .hljs { background: var(--code-bg); color: var(--fg); }
        }</style>
        """

        return HTMLTemplate.page(title: url.lastPathComponent, body: body, headExtra: head)
    }

    /// Reads text trying UTF-8, then falls back to a lossy 8-bit decode.
    static func readText(_ url: URL) -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let data = try? Data(contentsOf: url) {
            return String(decoding: data, as: UTF8.self)
        }
        return "*Could not read file.*"
    }
}
