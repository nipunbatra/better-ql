import Foundation

/// Syntax-highlighted preview for source files (.py, .js, .swift, …) using the
/// bundled highlight.js. Unknown extensions fall back to highlight.js auto-detect.
enum SourceCodeRenderer {
    static let cap = 600_000  // characters

    static func html(for url: URL) -> String {
        var raw = MarkdownRenderer.readText(url)
        var truncated = false
        if raw.count > cap { raw = String(raw.prefix(cap)); truncated = true }

        let lang = language(forExtension: url.pathExtension.lowercased())
        let cls = lang.map { "language-\($0)" } ?? ""
        let escaped = HTMLTemplate.escapeHTML(raw)
        let hljs = HTMLTemplate.resource("highlight.min", "js")
        let hljsCSS = HTMLTemplate.resource("highlight-github", "css")
        let note = truncated ? "<p class=\"bql-sub\">… truncated for preview.</p>" : ""

        let body = """
        <pre><code class="\(cls)">\(escaped)</code></pre>
        \(note)
        <script>\(hljs)</script>
        <script>
          if (window.hljs) document.querySelectorAll('pre code').forEach(function(b){
            try { hljs.highlightElement(b); } catch(e){}
          });
        </script>
        """
        let head = "<style>\(hljsCSS)</style>"
        return HTMLTemplate.page(title: url.lastPathComponent, body: body, headExtra: head)
    }

    /// True for files we want to claim and highlight.
    static func isCode(extension ext: String) -> Bool {
        language(forExtension: ext) != nil
    }

    /// Maps a file extension to a highlight.js language id. The important ones
    /// (Python, JS/TS, Swift, C/C++, Java, Go, Rust, Ruby, shell, …) are in the
    /// bundled common build; the rest gracefully fall back to auto-detection.
    static func language(forExtension ext: String) -> String? {
        switch ext {
        case "py", "pyw": return "python"
        case "js", "mjs", "cjs", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "swift": return "swift"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx": return "cpp"
        case "java": return "java"
        case "go": return "go"
        case "rs": return "rust"
        case "rb": return "ruby"
        case "sh", "bash", "zsh", "command": return "bash"
        case "php": return "php"
        case "kt", "kts": return "kotlin"
        case "cs": return "csharp"
        case "m", "mm": return "objectivec"
        case "scala", "sc": return "scala"
        case "r": return "r"
        case "lua": return "lua"
        case "pl", "pm": return "perl"
        case "dart": return "dart"
        case "sql": return "sql"
        case "yml", "yaml": return "yaml"
        case "toml", "ini", "cfg", "conf": return "ini"
        case "xml", "plist", "storyboard", "xib": return "xml"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "makefile", "mk": return "makefile"
        case "dockerfile": return "dockerfile"
        case "diff", "patch": return "diff"
        default: return nil
        }
    }
}
