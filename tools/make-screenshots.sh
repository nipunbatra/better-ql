#!/usr/bin/env bash
# Regenerate the landing-page screenshots by rendering the real previewers
# offscreen. No screen capture — reproducible and free of any desktop content.
set -euo pipefail
cd "$(dirname "$0")/.."

SRCS=(
  Sources/Preview/HTMLTemplate.swift
  Sources/Preview/MarkdownRenderer.swift
  Sources/Preview/JSONRenderer.swift
  Sources/Preview/CSVRenderer.swift
  Sources/Preview/ArchiveRenderer.swift
  Sources/Preview/TarRenderer.swift
  Sources/Preview/FolderRenderer.swift
  Sources/Preview/SourceCodeRenderer.swift
  Sources/Preview/Version.swift
  tools/main.swift
)

BIN="$(mktemp -d)/bql-screenshots"
echo "▸ Compiling…"
xcrun --sdk macosx swiftc "${SRCS[@]}" -o "$BIN"
echo "▸ Rendering…"
BQL_RESOURCE_DIR="$PWD/Resources" "$BIN" site/screenshots
echo "✓ Screenshots in site/screenshots/"
