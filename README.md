# TabDown

A Safari extension that saves all your open tabs to a markdown file, with optional AI summaries.

## Setup

1. Open the **TabDown** app
2. Click **Choose Folder** to pick where your tab exports will be saved
3. Go to **Safari > Settings > Extensions** and enable **TabDown**
4. For local (unsigned) builds, enable **Allow unsigned extensions** from the Develop menu each time you launch Safari

## Saving Tabs

Click the TabDown icon in the Safari toolbar to open the extension popup. From there you can:

- **Save Tabs** — exports all open tabs to a timestamped markdown file in your chosen folder
- **Include AI summaries** — generates an on-device summary for each tab using Apple Intelligence (requires macOS 26+)
- **Close tabs after saving** — after the export finishes, you'll be asked to confirm before any tabs are closed. Your currently active tab is always kept open.

Your checkbox preferences are remembered between sessions.

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
/path/to/TabDown.app/Contents/MacOS/TabDown --sync
```

This moves files that the extension has saved to the app group container into your configured output folder.
