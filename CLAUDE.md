# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS tool for exporting open Safari tabs to markdown files with AI-generated summaries using Apple Intelligence (on-device). Includes both a Python CLI tool and a native Safari Web Extension with companion app.

## Commands

```bash
# Run the main export script (Python CLI)
uv run --script export_tabs.py ~/Desktop/tabs.md

# Run without summaries
uv run --script export_tabs.py ~/Desktop/ --no-summarize

# Run tests (requires macOS 26+ with Apple Intelligence enabled)
uv run --script test_apple_summarize.py

# Manage daily launchd schedule
uv run --script export_tabs.py --install-schedule
uv run --script export_tabs.py --uninstall-schedule

# Build the Safari extension (macOS)
xcodebuild -project TabDown/TabDown.xcodeproj -scheme "TabDown (macOS)" -configuration Debug build -allowProvisioningUpdates
```

## Architecture

### Python CLI (`export_tabs.py`)

Main script using PEP 723 inline metadata (no pyproject.toml). It flows:

1. **Extract** tabs from Safari via JXA (`osascript` subprocess calls with JS templates)
2. **Deduplicate** URLs (strips fragments with `urldefrag()`)
3. **Filter** domains against `~/.config/safari-tabs/ignore-domains.txt`
4. **Summarize** page text using Apple Foundation Models SDK (`apple_intelligence` package, async)
5. **Render** markdown output
6. **Close** tabs optionally via JXA

Key implementation details:
- Suspended/unloaded tabs are detected by insufficient page text and auto-reloaded with a delay
- Summary validation rejects LLM refusals ("I apologize...", "I'm unable...") and tautological responses
- All logging goes to stderr; stdout is clean for piping
- The script uses `argparse` with scheduling subcommands that generate launchd plist files

### Safari Extension (`TabDown/`)

Native Safari Web Extension (MV3) with macOS companion app.

**Bundle IDs:**
- macOS App: `com.jcmultimedia.TabDown`
- macOS Extension: `com.jcmultimedia.TabDown.Extension`
- App Group: `group.com.jcmultimedia.TabDown`

**Key files:**
- `Shared (Extension)/SafariWebExtensionHandler.swift` — Central message dispatch (saveTabs, getSettings, getExcludedPatterns, setExcludedPatterns, summarize)
- `Shared (Extension)/TabExporter.swift` — Markdown generation, dedup, sort, filter
- `Shared (Extension)/BookmarkAccess.swift` — Security-scoped bookmark read/write for output folder
- `Shared (Extension)/Summarizer.swift` — Apple Intelligence wrapper (macOS 26+, FoundationModels)
- `Shared (Extension)/Resources/popup.js` — Extension popup UI and orchestration
- `Shared (Extension)/Resources/background.js` — Summarization orchestration (service worker)
- `Shared (Extension)/Resources/extract-content.js` — Content extraction injected into tabs
- `Shared (App)/ViewController.swift` — Companion app: folder picker, excluded URL patterns

**Message protocol** — all messages use `{ action: "...", ... }`:
- `saveTabs` — saves tabs to markdown file in selected output folder
- `getSettings` — returns whether output folder is configured
- `getExcludedPatterns` / `setExcludedPatterns` — manage URL exclusion patterns
- `summarize` — summarize text via Apple Intelligence

## Prerequisites

- macOS 26+ with Apple Intelligence enabled
- Safari > Settings > Advanced > "Show features for web developers" enabled
- Develop menu > "Allow JavaScript from Apple Events" enabled (for Python CLI)
