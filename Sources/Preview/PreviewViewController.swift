import Cocoa
import Quartz
import WebKit
import UniformTypeIdentifiers
import os.log

private let log = OSLog(subsystem: "com.nipunbatra.BetterQL", category: "preview")

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var completion: ((Error?) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        // The whole point of Better QL for HTML: let JavaScript run.
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Set the web view as the controller's own view (no wrapper container) and
        // add no key handling — this matches Apple's template and proven third-party
        // Quick Look extensions, where Escape dismisses the panel natively. A wrapper
        // view or custom key handling is what breaks Escape dismissal.
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        self.view = wv
        os_log("loadView done", log: log, type: .info)
    }

    /// Honour the appearance choice baked into the bundle (set by theme.sh).
    /// Setting the web view's NSAppearance makes CSS `prefers-color-scheme`
    /// resolve to it; "system" (the default) follows macOS automatically.
    private func applyTheme() {
        let theme = (try? String(contentsOf:
            Bundle(for: PreviewViewController.self).url(forResource: "theme", withExtension: "txt")
                ?? URL(fileURLWithPath: "/dev/null"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "system"
        switch theme {
        case "light": webView.appearance = NSAppearance(named: .aqua)
        case "dark":  webView.appearance = NSAppearance(named: .darkAqua)
        default:      webView.appearance = nil
        }
    }

    // MARK: QLPreviewingController

    func preparePreviewOfFile(at url: URL,
                              completionHandler handler: @escaping (Error?) -> Void) {
        os_log("preparePreviewOfFile: %{public}@", log: log, type: .default, url.path)
        self.completion = handler
        applyTheme()

        let isDir = directoryFlag(url)
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        let ext = url.pathExtension.lowercased()

        if isDir && !(type?.conforms(to: .bundle) ?? false) {
            os_log("branch: folder", log: log, type: .default)
            webView.loadHTMLString(FolderRenderer.html(for: url), baseURL: nil)
        } else if (type?.conforms(to: .zip) ?? false) || ext == "zip" {
            os_log("branch: zip", log: log, type: .default)
            webView.loadHTMLString(ArchiveRenderer.html(for: url), baseURL: nil)
        } else if ["tar", "gz", "tgz"].contains(ext) {
            os_log("branch: tar", log: log, type: .default)
            webView.loadHTMLString(TarRenderer.html(for: url), baseURL: nil)
        } else if (type?.conforms(to: .json) ?? false) || ext == "json" {
            os_log("branch: json", log: log, type: .default)
            webView.loadHTMLString(JSONRenderer.html(for: url), baseURL: nil)
        } else if (type?.conforms(to: .commaSeparatedText) ?? false) || ext == "csv" {
            os_log("branch: csv", log: log, type: .default)
            webView.loadHTMLString(CSVRenderer.html(for: url, delimiter: ","), baseURL: nil)
        } else if ext == "tsv" || (type?.identifier == "public.tab-separated-values-text") {
            os_log("branch: tsv", log: log, type: .default)
            webView.loadHTMLString(CSVRenderer.html(for: url, delimiter: "\t"), baseURL: nil)
        } else if SourceCodeRenderer.isCode(extension: ext) || (type?.conforms(to: .sourceCode) ?? false) {
            os_log("branch: source code", log: log, type: .default)
            webView.loadHTMLString(SourceCodeRenderer.html(for: url), baseURL: nil)
        } else if (type?.conforms(to: .html) ?? false) || ["html", "htm", "xhtml"].contains(ext) {
            os_log("branch: html", log: log, type: .default)
            // Read the file ourselves and load as a string with JS enabled. NOTE:
            // macOS routes public.html to its own system previewers (Safari + the
            // QuickLook generation extension) ahead of third-party ones, so this
            // path only runs if those are disabled. See README.
            let html = (try? String(contentsOf: url, encoding: .utf8))
                ?? MarkdownRenderer.readText(url)
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        } else {
            os_log("branch: markdown/text", log: log, type: .default)
            webView.loadHTMLString(MarkdownRenderer.html(for: url), baseURL: nil)
        }
        // Completion is signalled from the navigation delegate once content paints.
    }

    // MARK: WKNavigationDelegate — tell Quick Look only after the load settles

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        os_log("didFinish", log: log, type: .default)
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        os_log("didFail: %{public}@", log: log, type: .error, error.localizedDescription)
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        os_log("didFailProvisional: %{public}@", log: log, type: .error, error.localizedDescription)
        finish(error)
    }

    private func finish(_ error: Error?) {
        guard let c = completion else { return }
        completion = nil
        c(error)
    }

    private func directoryFlag(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
