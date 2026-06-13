import Foundation

enum JSONRenderer {
    static let cap = 800_000  // characters; avoid choking the highlighter on huge files

    static func html(for url: URL) -> String {
        var raw = MarkdownRenderer.readText(url)
        var truncated = false
        if raw.count > cap { raw = String(raw.prefix(cap)); truncated = true }

        // Pretty-print only if it parses and looks minified; otherwise keep as-is
        // so hand-formatted files are preserved exactly.
        let body: String
        if let data = raw.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            body = prettyPrint(raw)
        } else {
            body = raw
        }

        let escaped = FolderRenderer.esc(body)
        let hljs = HTMLTemplate.resource("highlight.min", "js")
        let hljsCSS = HTMLTemplate.resource("highlight-github", "css")
        let note = truncated ? "<p class=\"bql-sub\">… truncated for preview.</p>" : ""

        let content = """
        <pre><code class="language-json">\(escaped)</code></pre>
        \(note)
        <script>\(hljs)</script>
        <script>
          if (window.hljs) document.querySelectorAll('pre code').forEach(function(b){
            try { hljs.highlightElement(b); } catch(e) {}
          });
        </script>
        """
        let head = "<style>\(hljsCSS)</style>"
        return HTMLTemplate.page(title: url.lastPathComponent, body: content, headExtra: head)
    }

    /// Whitespace-normalising pretty-printer that preserves key order and string
    /// contents exactly (operates on the character stream, not a parsed model).
    static func prettyPrint(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + s.count / 4)
        var indent = 0
        var inString = false
        var escaped = false
        func pad(_ n: Int) -> String { String(repeating: "  ", count: max(0, n)) }

        for ch in s {
            if inString {
                out.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true; out.append(ch)
            case "{", "[": out.append(ch); indent += 1; out.append("\n"); out.append(pad(indent))
            case "}", "]": indent -= 1; out.append("\n"); out.append(pad(indent)); out.append(ch)
            case ",": out.append(ch); out.append("\n"); out.append(pad(indent))
            case ":": out.append(ch); out.append(" ")
            case " ", "\t", "\n", "\r": break
            default: out.append(ch)
            }
        }
        return out
    }
}
