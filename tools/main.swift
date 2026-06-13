import Cocoa
import WebKit

// Renders each Better QL preview offscreen and writes a PNG. Reuses the real
// renderers (compiled in alongside this file), so screenshots always match the
// shipping output. No screen capture, no desktop — fully reproducible.
//
// Usage: screenshots <out-dir>

setbuf(stdout, nil)
let fm = FileManager.default
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site/screenshots")
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

// ---- sample inputs ----
let tmp = fm.temporaryDirectory.appendingPathComponent("bql-shots-\(UUID().uuidString)")
try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)

func write(_ s: String, _ name: String, in dir: URL = tmp) -> URL {
    let u = dir.appendingPathComponent(name)
    try! s.write(to: u, atomically: true, encoding: .utf8)
    return u
}

func run(_ launch: String, _ args: [String], cwd: URL) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args; p.currentDirectoryURL = cwd
    try? p.run(); p.waitUntilExit()
}

func makePNG(_ size: Int, _ name: String, in dir: URL) {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSGradient(starting: NSColor.systemTeal, ending: NSColor.systemIndigo)?
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 45)
    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent(name))
    }
}

let md = write("""
# Better QL

A **markdown** preview — headings, tables, links, and highlighted code.

| Type | Rendered |
|------|----------|
| Tables | ✅ |
| Code | ✅ |

```python
def greet(name: str) -> str:
    return f"hello, {name}"
```

> Press Space in Finder. That's it.
""", "README.md")

let py = write("""
import numpy as np
from dataclasses import dataclass

@dataclass
class LinearModel:
    \"\"\"Gradient-descent linear regression.\"\"\"
    lr: float = 1e-3
    epochs: int = 200

    def fit(self, X, y):
        w = np.zeros(X.shape[1])
        for _ in range(self.epochs):
            w -= self.lr * X.T @ (X @ w - y) / len(y)
        return w
""", "model.py")

let json = write(#"{"name":"better-ql","version":1,"types":["md","code","json","csv","zip"],"nested":{"enabled":true,"ratio":0.42,"tags":["fast","native",null]}}"#, "config.json")

let csv = write("""
id,name,city,score
1,"Smith, John",Ahmedabad,98.5
2,Asha,"Mumbai, MH",91.0
3,Ravi,Delhi,88.2
4,"O'Neil, Sam",Bengaluru,95.7
""", "data.csv")

// folder with an image (for the thumbnail)
let folder = tmp.appendingPathComponent("project")
try! fm.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
_ = write("print('hi')", "main.py", in: folder.appendingPathComponent("src"))
_ = write("# Better QL", "README.md", in: folder)
_ = write("lr: 0.001\nepochs: 200", "train.yaml", in: folder)
makePNG(120, "logo.png", in: folder)

// zip
let zip = tmp.appendingPathComponent("release.zip")
run("/usr/bin/zip", ["-r", "-q", zip.path, "project"], cwd: tmp)

// ---- offscreen rendering ----
struct Job { let html: String; let name: String; let w: CGFloat; let h: CGFloat }
let jobs: [Job] = [
    Job(html: MarkdownRenderer.html(for: md), name: "markdown.png", w: 860, h: 640),
    Job(html: SourceCodeRenderer.html(for: py), name: "code.png", w: 860, h: 470),
    Job(html: JSONRenderer.html(for: json), name: "json.png", w: 860, h: 420),
    Job(html: CSVRenderer.html(for: csv), name: "csv.png", w: 860, h: 320),
    Job(html: FolderRenderer.html(for: folder), name: "folder.png", w: 860, h: 360),
    Job(html: ArchiveRenderer.html(for: zip), name: "zip.png", w: 860, h: 360),
]

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Shooter: NSObject, WKNavigationDelegate {
    var queue: [Job]
    let outDir: URL
    var webView: WKWebView!
    var window: NSWindow!
    var current = ""

    init(_ jobs: [Job], _ outDir: URL) { self.queue = jobs; self.outDir = outDir }

    func start() { next() }

    func next() {
        guard !queue.isEmpty else { print("done"); app.terminate(nil); return }
        let job = queue.removeFirst()
        current = job.name
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: job.w, height: job.h), configuration: cfg)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
        webView.loadHTMLString(job.html, baseURL: nil)
    }

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        // let marked/highlight.js finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let cfg = WKSnapshotConfiguration()
            wv.takeSnapshot(with: cfg) { image, error in
                if let image = image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.outDir.appendingPathComponent(self.current))
                    print("wrote \(self.current) (\(png.count) bytes)")
                } else {
                    print("FAILED \(self.current): \(String(describing: error))")
                }
                self.next()
            }
        }
    }
}

let shooter = Shooter(jobs, outDir)
shooter.start()
app.run()
