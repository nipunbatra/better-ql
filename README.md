# Better QL

[![CI](https://github.com/nipunbatra/better-ql/actions/workflows/ci.yml/badge.svg)](https://github.com/nipunbatra/better-ql/actions/workflows/ci.yml)
[![Deploy GitHub Pages](https://github.com/nipunbatra/better-ql/actions/workflows/pages.yml/badge.svg)](https://github.com/nipunbatra/better-ql/actions/workflows/pages.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

A richer Quick Look for macOS Finder. Press **Space** on a file and get a real
preview instead of an icon.

**Live site:** https://nipunbatra.github.io/better-ql/

| Type | What you get |
|------|--------------|
| **Markdown** (`.md`, `.markdown`, …) | Rendered HTML — headings, tables, links, and syntax-highlighted code blocks (via bundled `marked.js` + `highlight.js`). |
| **Source code** (`.py`, `.js`, `.ts`, `.swift`, `.c`, `.cpp`, `.java`, `.go`, `.rs`, `.rb`, `.sh`, …) | Syntax-highlighted via bundled `highlight.js`. |
| **JSON** (`.json`) | Pretty-printed (order preserved) and syntax-highlighted. |
| **CSV / TSV** (`.csv`, `.tsv`) | Rendered as a scrollable table with sticky header and row numbers (RFC-4180 quoting handled). |
| **Folders** | Full path, item counts, total size, and a table of **Name · Kind · Size · Modified** — sub-folders show their child count, and image files show **thumbnails**. |
| **Archives** (`.zip`, `.tar`, `.tar.gz`, `.tgz`, `.gz`) | Full file listing — paths, sizes, dates, compression ratio. Parsed natively (zip central directory; tar headers; gzip via the Compression framework). No third-party library. |

Everything renders through `WKWebView` with shared, dark-mode-aware styling.
Failures show a **copyable error page** instead of Quick Look's generic message.

## Appearance / themes

Previews follow your **macOS appearance automatically** (light in Light mode,
dark in Dark mode). To force a fixed theme:

```sh
./theme.sh light     # or: dark | system
```

(The extension is sandboxed, and a GUI picker would need an app group — which
requires a paid provisioning profile — so the theme is baked into the bundle and
applied via an ad-hoc re-sign. `theme.sh` handles that.)

## Install

Requirements: macOS 13+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
./install.sh
```

This builds with **ad-hoc "run-locally" signing** (no Apple Developer account
needed — it runs only on this Mac), installs `BetterQL.app` to `/Applications`,
registers the extension, and resets Quick Look.

If a type doesn't preview, enable **Better QL Preview** under
*System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look*.

```sh
./uninstall.sh   # remove it
```

## A note on `.html` with JavaScript

macOS routes `public.html` to its **own** Quick Look previewers (Safari's
`SafariQuickLookPreview` and the system `QLPreviewGenerationExtension`), which
run ahead of any third-party extension and **disable JavaScript** for security.
There is no priority API to outrank them, so Better QL deliberately does **not**
claim `.html` — Safari's (JS-less) preview stays in charge.

The only way to make Better QL handle `.html` with JavaScript running is to
disable those system previewers. That's invasive (it can affect other previews
and may need re-applying after macOS updates), so it's **opt-in**:

```sh
# Enable Better QL for .html (JS runs). Re-add "public.html" to
# Sources/Preview/Info.plist's QLSupportedContentTypes, then:
pluginkit -e ignore -i com.apple.Safari.SafariQuickLookPreview
./install.sh
# To revert:
pluginkit -e use -i com.apple.Safari.SafariQuickLookPreview
```

## How it's built

- `project.yml` — XcodeGen config: a tiny host app + a Quick Look Preview
  Extension (app-extension) target.
- `Sources/App/` — minimal SwiftUI host app (its only job is to carry/register
  the extension) and the **Markdown UTI declaration** (`UTImportedTypeDeclarations`)
  so `.md` reliably resolves to `net.daringfireball.markdown`.
- `Sources/Preview/` — the extension:
  - `PreviewViewController.swift` — `QLPreviewingController` that dispatches by
    file type and loads a `WKWebView`.
  - `MarkdownRenderer`, `JSONRenderer`, `CSVRenderer`, `FolderRenderer`,
    `ArchiveRenderer` (zip), `TarRenderer` (tar/gz), `HTMLTemplate`.
- `Resources/` — bundled `marked.min.js`, `highlight.min.js`, and CSS (offline;
  the extension is sandboxed with no network access to CDNs).

### Tests

Renderer logic (CSV quoting, JSON pretty-printing, zip/tar parsing, archive
cleanup) is covered by unit tests, run in CI on every push:

```sh
xcodegen generate
xcodebuild test -scheme BetterQLTests -destination 'platform=macOS'
```

### Why these entitlements
The extension is sandboxed (`com.apple.security.app-sandbox`) with
`files.user-selected.read-only` (read the previewed file) **and**
`network.client` — the latter is non-obvious but required: a sandboxed
`WKWebView` renders a blank/white view without it.
