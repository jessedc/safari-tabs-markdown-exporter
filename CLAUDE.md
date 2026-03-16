# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TabDown** is a native Safari extension (MV3) with a companion macOS app that exports all open Safari tabs to markdown files with optional AI-generated summaries via Apple Intelligence (on-device, macOS 26+).

## Build & Run

```bash
# Build from command line
xcodebuild -project TabDown/TabDown.xcodeproj \
  -scheme "TabDown (macOS)" \
  -configuration Debug \
  build -allowProvisioningUpdates

# Or open in Xcode and run (⌘R)
open TabDown/TabDown.xcodeproj
```

After building: Safari > Settings > Extensions > enable TabDown. For local builds, enable "Allow unsigned extensions" via Develop menu each Safari launch.

## CLI Sync Mode

```bash
/path/to/TabDown.app/Contents/MacOS/TabDown --sync
```

Moves pending exports from the app group container to the user-configured output folder.

## Architecture

**Two-process model** due to Safari extension sandbox restrictions:

1. **Extension** (JS + Swift): Extracts tab content, generates summaries, writes markdown to app group container (`group.com.jcmultimedia.TabDown/exports/`)
2. **Companion App** (SwiftUI): Resolves security-scoped bookmarks to move exports to the user-selected folder (`ExportSyncer`)

**Message flow:** popup.js → background.js → `browser.runtime.sendNativeMessage` → `SafariWebExtensionHandler.swift` (routes by `action` field) → `TabExporter` / `Summarizer`

**Content extraction pipeline:** `extract-content.js` injected into tabs → Mozilla Readability (falls back to `innerText`) → truncated to 10,000 chars → Summarizer truncates to 2,500 words for on-device model

**Markdown output format:** Two sections — domain-grouped links for scanning, then flat list with summaries for reading.

## Key Swift Files (under `TabDown/`)

- `Shared (Extension)/SafariWebExtensionHandler.swift` — Native message dispatch entry point
- `Shared (Extension)/TabExporter.swift` — Filtering, dedup, sorting, markdown rendering
- `Shared (Extension)/Summarizer.swift` — Apple Intelligence (`FoundationModels`) wrapper
- `Shared (App)/ExportSyncer.swift` — Moves files from extension container to user folder
- `macOS (App)/AppDelegate.swift` — Handles `--sync` CLI mode

## Key JS Files (under `TabDown/Shared (Extension)/Resources/`)

- `background.js` — Orchestrates tab extraction and summarization
- `extract-content.js` — Content extraction (Readability + innerText fallback)
- `popup.js` — Extension popup UI and state management

## Dependencies

- **DomainParser** (Swift Package) — Public Suffix List domain parsing
- **FoundationModels** (macOS 26+) — Apple Intelligence on-device summarization
- **Readability.js** (vendored) — Mozilla article extraction

## Debugging

- Extension background logs: Safari > Develop > Web Extension Background Content
- Popup logs: Right-click extension popup > Inspect Element
- Native logs: Console.app, filter by `com.jcmultimedia.TabDown.Extension`
