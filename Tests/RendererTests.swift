import XCTest
import Foundation

final class RendererTests: XCTestCase {

    // MARK: CSV — RFC-4180 quoting

    func testCSVQuoting() {
        let csv = "id,name,note\n1,\"Smith, John\",\"line1\nline2\"\n2,Asha,\"says \"\"hi\"\"\"\n"
        let (rows, capped) = CSVRenderer.parse(csv, delimiter: ",")
        XCTAssertFalse(capped)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["id", "name", "note"])
        XCTAssertEqual(rows[1][1], "Smith, John")     // comma inside quotes
        XCTAssertEqual(rows[1][2], "line1\nline2")     // newline inside quotes
        XCTAssertEqual(rows[2][2], "says \"hi\"")       // escaped double-quotes
    }

    func testTSVDelimiter() {
        let tsv = "a\tb\tc\n1\t2\t3\n"
        let (rows, _) = CSVRenderer.parse(tsv, delimiter: "\t")
        XCTAssertEqual(rows[0], ["a", "b", "c"])
        XCTAssertEqual(rows[1], ["1", "2", "3"])
    }

    // MARK: JSON — order-preserving pretty printer

    func testJSONPrettyPrintPreservesKeyOrder() {
        let pretty = JSONRenderer.prettyPrint("{\"b\":1,\"a\":[1,2],\"c\":\"x\"}")
        let b = pretty.range(of: "\"b\"")!.lowerBound
        let a = pretty.range(of: "\"a\"")!.lowerBound
        let c = pretty.range(of: "\"c\"")!.lowerBound
        XCTAssertTrue(b < a && a < c, "keys must keep source order")
        XCTAssertTrue(pretty.contains("\n"), "minified input should be expanded")
    }

    func testJSONLeavesStringContentUntouched() {
        let pretty = JSONRenderer.prettyPrint("{\"k\":\"a, b: c {x} [y]\"}")
        XCTAssertTrue(pretty.contains("\"a, b: c {x} [y]\""), "structural chars inside strings must not be reformatted")
    }

    // MARK: Source code — language mapping

    func testSourceLanguageMapping() {
        XCTAssertEqual(SourceCodeRenderer.language(forExtension: "py"), "python")
        XCTAssertEqual(SourceCodeRenderer.language(forExtension: "js"), "javascript")
        XCTAssertEqual(SourceCodeRenderer.language(forExtension: "swift"), "swift")
        XCTAssertEqual(SourceCodeRenderer.language(forExtension: "cpp"), "cpp")
        XCTAssertEqual(SourceCodeRenderer.language(forExtension: "rs"), "rust")
        XCTAssertNil(SourceCodeRenderer.language(forExtension: "md"))
        XCTAssertTrue(SourceCodeRenderer.isCode(extension: "go"))
        XCTAssertFalse(SourceCodeRenderer.isCode(extension: "md"))
    }

    // MARK: Zip — central directory parsing

    func testZipListing() throws {
        let dir = try tempDir()
        let src = dir.appendingPathComponent("proj/src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "print('hi')".write(to: src.appendingPathComponent("main.py"), atomically: true, encoding: .utf8)
        try "# readme".write(to: dir.appendingPathComponent("proj/README.md"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("a.zip")
        try run("/usr/bin/zip", ["-r", "-q", zip.path, "proj"], cwd: dir)

        let entries = try ArchiveRenderer.readEntries(zip)
        let paths = entries.map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("main.py") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("README.md") })
        let py = entries.first { $0.path.hasSuffix("main.py") }!
        XCTAssertEqual(py.size, UInt64("print('hi')".utf8.count))
    }

    // MARK: Tar.gz — gzip inflate + tar headers + macOS-artifact filtering

    func testTarGzListingAndCleanup() throws {
        let dir = try tempDir()
        let model = dir.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try "weights".write(to: model.appendingPathComponent("w.bin"), atomically: true, encoding: .utf8)
        let tgz = dir.appendingPathComponent("m.tar.gz")
        try run("/usr/bin/tar", ["-czf", tgz.path, "model"], cwd: dir)

        let html = TarRenderer.html(for: tgz)
        XCTAssertTrue(html.contains("w.bin"), "real file should be listed")
        XCTAssertFalse(html.contains("PaxHeader"), "macOS pax headers must be filtered out")
        XCTAssertFalse(html.contains("Couldn't preview"), "should not be an error page")
    }

    // MARK: Folder

    func testFolderListing() throws {
        let dir = try tempDir()
        try "x".write(to: dir.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        let html = FolderRenderer.html(for: dir)
        XCTAssertTrue(html.contains("alpha.txt"))
        XCTAssertTrue(html.contains("subdir"))
    }

    // MARK: helpers

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bqltest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func run(_ launch: String, _ args: [String], cwd: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        p.currentDirectoryURL = cwd
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
