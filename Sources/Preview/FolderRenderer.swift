import Foundation
import UniformTypeIdentifiers
import ImageIO
import AppKit

enum FolderRenderer {
    static let thumbBudgetDefault = 120  // cap thumbnails so big folders stay snappy

    /// Small base64 PNG thumbnail for an image file, or nil. Uses ImageIO so it
    /// works for any image format Quick Look itself supports.
    static func thumbnailURI(_ url: URL, maxPixel: Int = 40) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
    static func html(for url: URL) -> String {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .fileSizeKey,
            .totalFileAllocatedSizeKey, .contentModificationDateKey, .contentTypeKey,
        ]

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys,
                options: [.skipsSubdirectoryDescendants])
        } catch {
            let body = "<div class=\"bql-head\"><h1>📁 \(esc(url.lastPathComponent))</h1></div>"
                + "<p class=\"bql-sub\">Could not read folder contents.</p>"
            return HTMLTemplate.page(title: url.lastPathComponent, body: body)
        }

        struct Row {
            let name: String; let isDir: Bool; let size: Int64
            let date: Date?; let icon: String; let kind: String
            let childCount: Int?; let thumb: String?
        }

        var thumbBudget = thumbBudgetDefault
        var rows: [Row] = entries.compactMap { item in
            let name = item.lastPathComponent
            if name.hasPrefix(".") { return nil } // hide dotfiles
            let v = try? item.resourceValues(forKeys: Set(keys))
            let isPackage = v?.isPackage ?? false
            let isDir = (v?.isDirectory ?? false) && !isPackage
            let size = Int64(v?.fileSize ?? v?.totalFileAllocatedSize ?? 0)
            let childCount = isDir ? childCount(of: item, fm: fm) : nil

            var thumb: String? = nil
            if !isDir, thumbBudget > 0, v?.contentType?.conforms(to: .image) == true {
                thumb = thumbnailURI(item)
                if thumb != nil { thumbBudget -= 1 }
            }

            return Row(name: name, isDir: isDir, size: size,
                       date: v?.contentModificationDate,
                       icon: icon(for: v?.contentType, isDir: isDir, isPackage: isPackage),
                       kind: kind(for: v?.contentType, isDir: isDir, isPackage: isPackage, name: name),
                       childCount: childCount, thumb: thumb)
        }

        // Folders first, then files; each alphabetical, case-insensitive.
        rows.sort { a, b in
            if a.isDir != b.isDir { return a.isDir && !b.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        let dirCount = rows.filter { $0.isDir }.count
        let fileCount = rows.count - dirCount
        let totalSize = rows.filter { !$0.isDir }.reduce(Int64(0)) { $0 + $1.size }
        let summary = "\(dirCount) folder\(dirCount == 1 ? "" : "s") · "
            + "\(fileCount) file\(fileCount == 1 ? "" : "s")"
            + (totalSize > 0 ? " · \(byteString(totalSize))" : "")

        let df = DateFormatter()
        df.dateStyle = .medium; df.timeStyle = .short

        let body = rows.map { r -> String in
            let cls = r.isDir ? "dir" : "file"
            let sizeCell: String
            if r.isDir {
                sizeCell = r.childCount.map { "\($0) item\($0 == 1 ? "" : "s")" } ?? "—"
            } else {
                sizeCell = byteString(r.size)
            }
            let dateCell = r.date.map { df.string(from: $0) } ?? ""
            let iconHTML = r.thumb.map { "<img class=\"thumb\" src=\"\($0)\">" } ?? r.icon
            return """
            <tr class="\(cls)">
              <td class="name"><span class="ic">\(iconHTML)</span>\(esc(r.name))</td>
              <td class="kind">\(esc(r.kind))</td>
              <td class="size">\(sizeCell)</td>
              <td class="date">\(dateCell)</td>
            </tr>
            """
        }.joined(separator: "\n")

        let table = rows.isEmpty
            ? "<p class=\"bql-sub\">This folder is empty.</p>"
            : """
              <table class="bql-list">
                <thead><tr><th>Name</th><th class="kind">Kind</th><th class="size">Size</th><th class="date">Modified</th></tr></thead>
                <tbody>\(body)</tbody>
              </table>
              """

        let header = """
        <div class="bql-head"><h1>📁 \(esc(url.lastPathComponent))</h1></div>
        <p class="bql-sub">\(esc(prettyPath(url))) · \(summary)</p>
        \(table)
        """
        return HTMLTemplate.page(title: url.lastPathComponent, body: header)
    }

    /// Cheap one-level child count (non-dotfiles) for a subfolder.
    static func childCount(of url: URL, fm: FileManager) -> Int? {
        guard let items = try? fm.contentsOfDirectory(atPath: url.path) else { return nil }
        return items.filter { !$0.hasPrefix(".") }.count
    }

    static func prettyPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.deletingLastPathComponent().path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    static func kind(for type: UTType?, isDir: Bool, isPackage: Bool, name: String) -> String {
        if isPackage { return type?.localizedDescription ?? "Package" }
        if isDir { return "Folder" }
        if let d = type?.localizedDescription { return d.prefix(1).uppercased() + d.dropFirst() }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
    }

    static func icon(for type: UTType?, isDir: Bool, isPackage: Bool) -> String {
        if isDir { return "📁" }
        if isPackage { return "📦" }
        guard let t = type else { return "📄" }
        if t.conforms(to: .image) { return "🖼️" }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return "🎬" }
        if t.conforms(to: .audio) { return "🎵" }
        if t.conforms(to: .archive) || t.conforms(to: .zip) { return "🗜️" }
        if t.conforms(to: .pdf) { return "📕" }
        if t.conforms(to: .sourceCode) || t.conforms(to: .script) { return "📜" }
        if t.conforms(to: .text) { return "📝" }
        return "📄"
    }

    static func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
