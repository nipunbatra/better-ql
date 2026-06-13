import SwiftUI

@main
struct BetterQLApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    private let types: [(String, String)] = [
        ("Markdown", ".md  ·  headings, tables, highlighted code"),
        ("Code", ".py · .js · .swift · .go · .rs · …  ·  highlighted"),
        ("Data", ".json · .csv · .tsv  ·  pretty-printed / tables"),
        ("Archives", ".zip · .tar · .tar.gz  ·  full file listing"),
        ("Folders", "path, kind, size, dates + image thumbnails"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Better QL").font(.largeTitle.bold())
                    Text("A richer Quick Look for Finder")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(types, id: \.0) { t in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(t.0).bold().frame(width: 90, alignment: .leading)
                    Text(t.1).foregroundStyle(.secondary).font(.callout)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance").font(.headline)
                Text("Previews follow your macOS appearance automatically. To force a fixed theme, run **./theme.sh light**, **dark**, or **system**.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("To enable").font(.headline)
                Text("System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look — turn on **Better QL Preview**.")
                Text("Then select any file above in Finder and press the Space bar.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(28)
        .frame(width: 460)
    }
}
