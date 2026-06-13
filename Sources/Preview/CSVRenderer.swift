import Foundation

enum CSVRenderer {
    static let maxRows = 1000
    static let maxCols = 60

    static func html(for url: URL, delimiter: Character = ",") -> String {
        let raw = MarkdownRenderer.readText(url)
        let (rows, moreRows) = parse(raw, delimiter: delimiter)
        let name = url.lastPathComponent

        guard let header = rows.first else {
            let body = "<div class=\"bql-head\"><h1>📊 \(FolderRenderer.esc(name))</h1></div>"
                + "<p class=\"bql-sub\">Empty file.</p>"
            return HTMLTemplate.page(title: name, body: body)
        }

        let colCount = min(rows.map { $0.count }.max() ?? 0, maxCols)
        let bodyRows = rows.dropFirst()

        func cells(_ r: [String], tag: String) -> String {
            (0..<colCount).map { i in
                let v = i < r.count ? r[i] : ""
                return "<\(tag)>\(FolderRenderer.esc(v))</\(tag)>"
            }.joined()
        }

        let thead = "<thead><tr><th class=\"rownum\">#</th>" + cells(header, tag: "th") + "</tr></thead>"
        let tbody = bodyRows.enumerated().map { idx, r in
            "<tr><td class=\"rownum\">\(idx + 1)</td>" + cells(r, tag: "td") + "</tr>"
        }.joined(separator: "\n")

        let colNote = (rows.map { $0.count }.max() ?? 0) > maxCols
            ? " · showing first \(maxCols) columns" : ""
        let rowNote = moreRows ? " · showing first \(maxRows) rows" : ""
        let summary = "\(bodyRows.count) row\(bodyRows.count == 1 ? "" : "s") · \(header.count) columns\(colNote)\(rowNote)"

        let body = """
        <div class="bql-head"><h1>📊 \(FolderRenderer.esc(name))</h1></div>
        <p class="bql-sub">\(summary)</p>
        <div class="bql-scroll">
        <table class="bql-csv">\(thead)<tbody>\(tbody)</tbody></table>
        </div>
        """
        return HTMLTemplate.page(title: name, body: body)
    }

    /// RFC-4180-ish parser: handles quoted fields, escaped quotes (""),
    /// and delimiters/newlines inside quotes. Returns rows and whether capped.
    static func parse(_ s: String, delimiter: Character) -> ([[String]], Bool) {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(s)
        var i = 0
        var capped = false

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false; i += 1; continue
                }
                field.append(c); i += 1; continue
            }
            if c == "\"" { inQuotes = true; i += 1; continue }
            if c == delimiter { row.append(field); field = ""; i += 1; continue }
            if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""; rows.append(row); row = []
                i += 1
                if rows.count >= maxRows { capped = true; break }
                continue
            }
            field.append(c); i += 1
        }
        if !capped && (!field.isEmpty || !row.isEmpty) { row.append(field); rows.append(row) }
        return (rows, capped)
    }
}
