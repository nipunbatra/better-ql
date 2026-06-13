import Foundation
import Compression

/// Lists .tar, .tar.gz/.tgz, and .gz archives.
/// - Uncompressed .tar is walked via FileHandle seeking (reads only 512-byte
///   headers, so it's fast even on huge tarballs).
/// - .gz is inflated with the Compression framework; if the result is a tar it's
///   listed, otherwise a single-file summary is shown (name + sizes from the
///   gzip header/trailer, no full decompression needed).
enum TarRenderer {
    struct Entry { let name: String; let size: UInt64; let isDir: Bool; let date: Date? }

    static let entryCap = 5000
    static let maxCompressedRead = 200 * 1024 * 1024   // 200 MB
    static let maxDecompressed = 400 * 1024 * 1024     // 400 MB

    static func html(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let isGzip = lower.hasSuffix(".gz") || lower.hasSuffix(".tgz")

        var entries: [Entry]? = nil
        var singleFile: (String, UInt64)? = nil

        if !isGzip {
            entries = parseTarFile(url)
        } else {
            guard let comp = try? readCapped(url, max: maxCompressedRead),
                  let inflated = gunzip(comp, limit: maxDecompressed) else {
                return errorPage(name, "Could not read this gzip archive.")
            }
            if looksLikeTar(inflated) {
                entries = parseTarData(inflated)
            } else {
                // Plain single-file gzip — report the embedded name + uncompressed size.
                let embedded = gzipOriginalName(comp) ?? (lower.hasSuffix(".gz") ? String(name.dropLast(3)) : name)
                singleFile = (embedded, UInt64(inflated.count))
            }
        }

        if let one = singleFile {
            let body = """
            <div class="bql-head"><h1>🗜️ \(esc(name))</h1></div>
            <p class="bql-sub">Gzip-compressed file · 1 item</p>
            <table class="bql-list">
              <thead><tr><th>Name</th><th class="size">Uncompressed</th></tr></thead>
              <tbody><tr class="file"><td class="name"><span class="ic">📄</span>\(esc(one.0))</td>
              <td class="size">\(byteString(Int64(one.1)))</td></tr></tbody>
            </table>
            """
            return HTMLTemplate.page(title: name, body: body)
        }

        guard let list = entries else { return errorPage(name, "Could not read this archive.") }
        return listing(name: name, entries: list)
    }

    // MARK: rendering

    private static func listing(name: String, entries: [Entry]) -> String {
        let files = entries.filter { !$0.isDir }
        let dirs = entries.filter { $0.isDir }
        let total = files.reduce(Int64(0)) { $0 + Int64($1.size) }
        let summary = "\(files.count) file\(files.count == 1 ? "" : "s")"
            + (dirs.isEmpty ? "" : " · \(dirs.count) folder\(dirs.count == 1 ? "" : "s")")
            + (total > 0 ? " · \(byteString(total)) uncompressed" : "")

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        let shown = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let rows = shown.map { e -> String in
            let date = e.date.map { df.string(from: $0) } ?? ""
            return """
            <tr class="file"><td class="name"><span class="ic">📄</span>\(esc(e.name))</td>
            <td class="size">\(byteString(Int64(e.size)))</td><td class="date">\(date)</td></tr>
            """
        }.joined(separator: "\n")

        let table = files.isEmpty
            ? "<p class=\"bql-sub\">This archive is empty.</p>"
            : """
              <table class="bql-list">
                <thead><tr><th>Name</th><th class="size">Size</th><th class="date">Modified</th></tr></thead>
                <tbody>\(rows)</tbody></table>
              """
        let body = """
        <div class="bql-head"><h1>🗜️ \(esc(name))</h1></div>
        <p class="bql-sub">\(summary)</p>
        \(table)
        """
        return HTMLTemplate.page(title: name, body: body)
    }

    private static func errorPage(_ name: String, _ msg: String) -> String {
        HTMLTemplate.errorPage(title: name, summary: msg,
            details: "File: \(name)\nKind: archive (tar/gz)\nBetter QL \(BetterQL.version)")
    }

    // MARK: tar walking

    private static func parseTarFile(_ url: URL) -> [Entry]? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let fileSize = (try? h.seekToEnd()) ?? 0
        var off: UInt64 = 0
        var entries: [Entry] = []
        var longName: String? = nil

        while off + 512 <= fileSize {
            try? h.seek(toOffset: off)
            guard let hdr = try? h.read(upToCount: 512), hdr.count == 512 else { break }
            if hdr.allSatisfy({ $0 == 0 }) { break }

            let size = octal(hdr, 124, 12)
            let typeflag = hdr[hdr.startIndex + 156]

            if typeflag == 0x4C { // 'L' GNU long name — payload is next entry's name
                if let nameData = try? h.read(upToCount: Int(size)) {
                    longName = trimNUL(String(decoding: nameData, as: UTF8.self))
                }
                off += 512 + roundUp512(size); continue
            }
            if typeflag == 0x78 || typeflag == 0x67 { // pax extended/global header — metadata, skip
                off += 512 + roundUp512(size); continue
            }
            let entry = makeEntry(hdr, size: size, longName: longName)
            longName = nil
            off += 512 + roundUp512(size)
            if !shouldHide(entry.name) {
                entries.append(entry)
                if entries.count >= entryCap { break }
            }
        }
        return entries
    }

    private static func parseTarData(_ data: Data) -> [Entry] {
        var off = 0
        var entries: [Entry] = []
        var longName: String? = nil
        let n = data.count

        while off + 512 <= n {
            let hdr = data.subdata(in: (data.startIndex + off)..<(data.startIndex + off + 512))
            if hdr.allSatisfy({ $0 == 0 }) { break }
            let size = octal(hdr, 124, 12)
            let typeflag = hdr[hdr.startIndex + 156]

            if typeflag == 0x4C {
                let dataStart = off + 512
                if dataStart + Int(size) <= n {
                    let nameData = data.subdata(in: (data.startIndex + dataStart)..<(data.startIndex + dataStart + Int(size)))
                    longName = trimNUL(String(decoding: nameData, as: UTF8.self))
                }
                off += 512 + Int(roundUp512(size)); continue
            }
            if typeflag == 0x78 || typeflag == 0x67 { // pax extended/global header — metadata, skip
                off += 512 + Int(roundUp512(size)); continue
            }
            let entry = makeEntry(hdr, size: size, longName: longName)
            longName = nil
            off += 512 + Int(roundUp512(size))
            if !shouldHide(entry.name) {
                entries.append(entry)
                if entries.count >= entryCap { break }
            }
        }
        return entries
    }

    private static func makeEntry(_ hdr: Data, size: UInt64, longName: String?) -> Entry {
        let typeflag = hdr[hdr.startIndex + 156]
        let rawName = cString(hdr, 0, 100)
        let prefix = cString(hdr, 345, 155)
        let name = longName ?? (prefix.isEmpty ? rawName : prefix + "/" + rawName)
        let isDir = typeflag == 0x35 /* '5' */ || name.hasSuffix("/")
        let mtime = octal(hdr, 136, 12)
        let date = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
        return Entry(name: name, size: isDir ? 0 : size, isDir: isDir, date: date)
    }

    private static func looksLikeTar(_ d: Data) -> Bool {
        guard d.count >= 263 else { return false }
        let s = d.startIndex + 257
        // "ustar"
        return d[s] == 0x75 && d[s+1] == 0x73 && d[s+2] == 0x74 && d[s+3] == 0x61 && d[s+4] == 0x72
    }

    // MARK: gzip

    private static func readCapped(_ url: URL, max: Int) throws -> Data {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return (try h.read(upToCount: max)) ?? Data()
    }

    private static func gzipOriginalName(_ data: Data) -> String? {
        guard data.count > 10, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return nil }
        let flags = data[data.startIndex + 3]
        guard flags & 0x08 != 0 else { return nil } // FNAME present?
        var off = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard data.count > off + 2 else { return nil }
            let xlen = Int(data[data.startIndex + off]) | (Int(data[data.startIndex + off + 1]) << 8)
            off += 2 + xlen
        }
        var bytes: [UInt8] = []
        while off < data.count {
            let b = data[data.startIndex + off]; off += 1
            if b == 0 { break }
            bytes.append(b)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    private static func gunzip(_ data: Data, limit: Int) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b, data[data.startIndex + 2] == 8 else { return nil }
        let flags = data[data.startIndex + 3]
        var off = 10
        if flags & 0x04 != 0 {
            guard data.count > off + 2 else { return nil }
            let xlen = Int(data[data.startIndex + off]) | (Int(data[data.startIndex + off + 1]) << 8)
            off += 2 + xlen
        }
        if flags & 0x08 != 0 { while off < data.count && data[data.startIndex + off] != 0 { off += 1 }; off += 1 }
        if flags & 0x10 != 0 { while off < data.count && data[data.startIndex + off] != 0 { off += 1 }; off += 1 }
        if flags & 0x02 != 0 { off += 2 }
        guard off < data.count else { return nil }
        let deflate = data.subdata(in: (data.startIndex + off)..<data.endIndex)
        return rawInflate(deflate, limit: limit)
    }

    /// Apple's COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), exactly what sits
    /// inside a gzip wrapper once the header is stripped.
    private static func rawInflate(_ input: Data, limit: Int) -> Data? {
        let bufSize = 65_536
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { dst.deallocate() }
        var output = Data()

        return input.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> Data? in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
            streamPtr.pointee.src_ptr = base
            streamPtr.pointee.src_size = input.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                streamPtr.pointee.dst_ptr = dst
                streamPtr.pointee.dst_size = bufSize
                let status = compression_stream_process(streamPtr, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufSize - streamPtr.pointee.dst_size
                    output.append(dst, count: produced)
                    if status == COMPRESSION_STATUS_END { return output }
                    if output.count > limit { return output }
                    if produced == 0 { return output.isEmpty ? nil : output } // no progress — never spin
                default:
                    return output.isEmpty ? nil : output
                }
            }
        }
    }

    // MARK: byte helpers

    private static func octal(_ d: Data, _ off: Int, _ len: Int) -> UInt64 {
        let start = d.startIndex + off
        var result: UInt64 = 0
        var started = false
        for i in 0..<len {
            let b = d[start + i]
            if b == 0x20 { if started { break } else { continue } }
            if b == 0 { break }
            if b >= 0x30 && b <= 0x37 { result = result * 8 + UInt64(b - 0x30); started = true }
            else { break }
        }
        return result
    }

    private static func cString(_ d: Data, _ off: Int, _ len: Int) -> String {
        let start = d.startIndex + off
        var bytes: [UInt8] = []
        for i in 0..<len {
            let b = d[start + i]
            if b == 0 { break }
            bytes.append(b)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Hide macOS tar artifacts: AppleDouble (._*) sidecars and PaxHeader entries.
    private static func shouldHide(_ name: String) -> Bool {
        let base = (name as NSString).lastPathComponent
        if base.hasPrefix("._") || base == ".DS_Store" { return true }
        if name.contains("/PaxHeader/") || base == "PaxHeader" { return true }
        return false
    }

    private static func roundUp512(_ n: UInt64) -> UInt64 { (n + 511) / 512 * 512 }
    private static func trimNUL(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) }
    private static func esc(_ s: String) -> String { FolderRenderer.esc(s) }
    private static func byteString(_ n: Int64) -> String { FolderRenderer.byteString(n) }
}
