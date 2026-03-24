# Safari "TabDown" Extension

<p align="center">
  <img src="TabDown/Shared (Extension)/Resources/images/icon-256.png" alt="TabDown icon" width="128">
</p>

A Safari extension that saves all your open tabs to a markdown file. It will optionally summarize the page with Apple Intelligence, and close the tabs afterwards.

## Releases

The most recent notarized release is available in the [releases](https://github.com/jessedc/safari-tabs-markdown-exporter/releases).

## Setup

1. Copy **TabDown.app** to your `/Applications` directory
2. Open the **TabDown** app
2. Click **Choose Folder** to pick where your tab exports will be saved
3. Go to **Safari > Settings > Extensions** and enable **TabDown**

_For local (unsigned) builds, enable **Allow unsigned extensions** from the Develop menu each time you launch Safari._

## Saving Tabs

Click the TabDown icon in the Safari toolbar to open the extension popup. From there you can:

- **Save Tabs** — exports all open tabs to a timestamped markdown file in the extension's sandbox container
- **Include AI summaries** — generates an on-device summary for each tab using Apple Intelligence (requires macOS 26+)
- **Close tabs after saving** — after the export finishes, you'll be asked to confirm before any tabs are closed. Your currently active tab is always kept open.

Your checkbox preferences are remembered between sessions.

**Note:** Exported files are initially stored in the extension's sandbox container. To move them to your chosen folder, either open the **TabDown** app or run the `--sync` command (see [Automation](#automation) below).

## What Gets Exported

The exported markdown file contains:

1. **Links grouped by domain** — for quick scanning
2. **Summaries section** — each link with its AI-generated summary (only when summaries are enabled)

Tabs are automatically deduplicated (URLs differing only by fragment are treated as the same) and sorted alphabetically by domain and path.

## Filtering Tabs

Some tabs are always excluded from exports, like Safari built-in pages (`favorites://`, `bookmarks://`, `about:blank`).

You can add your own exclusions in the TabDown companion app under **Excluded URL Patterns**. Enter a host or host/path prefix (e.g. `mail.google.com`) and any matching tabs will be skipped during export.

## Automation

You can run TabDown from the command line to sync any pending exports to your output folder:

```
/Applications/TabDown.app/Contents/MacOS/TabDown --sync
```

This moves any pending exports from the extension's sandbox container into your configured output folder. Opening the TabDown app does the same thing automatically.
