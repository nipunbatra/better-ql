import Foundation

/// Lists the contents of a .zip by parsing its central directory directly.
/// No third-party dependency — reads only the tail + central directory, so it
/// stays fast even on large archives.
enum ArchiveRenderer {

    struct Entry {
        let path: String
        let size: UInt64        // uncompressed
        let compressed: UInt64
        let isDir: Bool
        let date: Date?
    }

    static let displayCap = 2000

    static func html(for url: URL) -> String {
        let name = url.lastPathComponent
        guard let entries = try? readEntries(url) else {
            return HTMLTemplate.errorPage(title: name,
                summary: "Could not read this archive (it may be encrypted, split, or use ZIP64).",
                details: "File: \(name)\nKind: zip archive\nBetter QL \(BetterQL.version)")
        }

        let files = entries.filter { !$0.isDir }
        let dirs = entries.filter { $0.isDir }
        let totalUncompressed = files.reduce(UInt64(0)) { $0 + $1.size }
        let totalCompressed = files.reduce(UInt64(0)) { $0 + $1.compressed }
        let ratio = totalUncompressed > 0
            ? Int((1.0 - Double(totalCompressed) / Double(totalUncompressed)) * 100) : 0

        let summary = "\(files.count) file\(files.count == 1 ? "" : "s")"
            + (dirs.isEmpty ? "" : " · \(dirs.count) folder\(dirs.count == 1 ? "" : "s")")
            + " · \(byteString(Int64(totalUncompressed))) uncompressed"
            + (totalUncompressed > 0 ? " · \(ratio)% smaller" : "")

        // Sort by path so directory groupings read naturally.
        let shown = files.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        let capped = Array(shown.prefix(displayCap))

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short

        let rows = capped.map { e -> String in
            let dateCell = e.date.map { df.string(from: $0) } ?? ""
            return """
            <tr class="file">
              <td class="name"><span class="ic">\(icon(forPath: e.path))</span>\(esc(e.path))</td>
              <td class="size">\(byteString(Int64(e.size)))</td>
              <td class="date">\(dateCell)</td>
            </tr>
            """
        }.joined(separator: "\n")

        let moreNote = shown.count > capped.count
            ? "<p class=\"bql-sub\">… and \(shown.count - capped.count) more entries not shown.</p>"
            : ""

        let table = files.isEmpty
            ? "<p class=\"bql-sub\">This archive is empty.</p>"
            : """
              <table class="bql-list">
                <thead><tr><th>Name</th><th class="size">Size</th><th class="date">Modified</th></tr></thead>
                <tbody>\(rows)</tbody>
              </table>
              \(moreNote)
              """

        let body = """
        <div class="bql-head"><h1>🗜️ \(esc(name))</h1></div>
        <p class="bql-sub">\(summary)</p>
        \(table)
        """
        return HTMLTemplate.page(title: name, body: body)
    }

    // MARK: ZIP central-directory parsing

    private enum ZipError: Error { case notZip }

    static func readEntries(_ url: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize > 22 else { throw ZipError.notZip }

        // End-of-central-directory lives in the last 22 bytes + up to 64KB comment.
        let tailLen = Int(min(fileSize, UInt64(66_000)))
        try handle.seek(toOffset: fileSize - UInt64(tailLen))
        let tail = handle.readData(ofLength: tailLen)

        guard let eocd = lastSignature([0x50, 0x4b, 0x05, 0x06], in: tail) else { throw ZipError.notZip }

        let cdSize = u32(tail, eocd + 12)
        let cdOffset = u32(tail, eocd + 16)
        // ZIP64 sentinel — out of scope for this lister.
        guard cdOffset != 0xFFFF_FFFF, cdSize != 0xFFFF_FFFF else { throw ZipError.notZip }

        try handle.seek(toOffset: UInt64(cdOffset))
        let cd = handle.readData(ofLength: Int(cdSize))

        var entries: [Entry] = []
        var i = 0
        while i + 46 <= cd.count {
            guard cd[cd.startIndex + i] == 0x50, cd[cd.startIndex + i + 1] == 0x4b,
                  cd[cd.startIndex + i + 2] == 0x01, cd[cd.startIndex + i + 3] == 0x02 else { break }

            let compSize = u32(cd, i + 20)
            let uncompSize = u32(cd, i + 24)
            let nameLen = Int(u16(cd, i + 28))
            let extraLen = Int(u16(cd, i + 30))
            let commentLen = Int(u16(cd, i + 32))
            let dosTime = u16(cd, i + 12)
            let dosDate = u16(cd, i + 14)

            let nameStart = cd.startIndex + i + 46
            let nameData = cd.subdata(in: nameStart..<min(nameStart + nameLen, cd.endIndex))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(
                path: name,
                size: UInt64(uncompSize),
                compressed: UInt64(compSize),
                isDir: name.hasSuffix("/"),
                date: dosDateTime(date: dosDate, time: dosTime)))

            i += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    // MARK: byte helpers (little-endian, slice-safe)

    private static func u16(_ d: Data, _ off: Int) -> UInt16 {
        let i = d.startIndex + off
        guard i + 1 < d.endIndex else { return 0 }
        return UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }

    private static func u32(_ d: Data, _ off: Int) -> UInt32 {
        let i = d.startIndex + off
        guard i + 3 < d.endIndex else { return 0 }
        return UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16) | (UInt32(d[i + 3]) << 24)
    }

    private static func lastSignature(_ sig: [UInt8], in d: Data) -> Int? {
        guard d.count >= 4 else { return nil }
        var idx = d.count - 4
        while idx >= 0 {
            let s = d.startIndex + idx
            if d[s] == sig[0], d[s + 1] == sig[1], d[s + 2] == sig[2], d[s + 3] == sig[3] { return idx }
            idx -= 1
        }
        return nil
    }

    private static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        let day = Int(date & 0x1F)
        let month = Int((date >> 5) & 0x0F)
        let year = Int((date >> 9) & 0x7F) + 1980
        guard day > 0, month > 0 else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = Int((time >> 11) & 0x1F)
        c.minute = Int((time >> 5) & 0x3F)
        c.second = Int(time & 0x1F) * 2
        return Calendar.current.date(from: c)
    }

    // MARK: display helpers

    private static func icon(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff", "svg": return "🖼️"
        case "mp4", "mov", "avi", "mkv", "webm": return "🎬"
        case "mp3", "wav", "aac", "flac", "m4a": return "🎵"
        case "pdf": return "📕"
        case "zip", "gz", "tar", "7z", "rar": return "🗜️"
        case "md", "markdown", "txt", "rtf": return "📝"
        case "swift", "py", "js", "ts", "c", "cpp", "h", "java", "go", "rs", "rb", "sh", "html", "css", "json", "yml", "yaml", "xml":
            return "📜"
        default: return "📄"
        }
    }

    private static func esc(_ s: String) -> String { FolderRenderer.esc(s) }
    private static func byteString(_ n: Int64) -> String { FolderRenderer.byteString(n) }
}
