# Safari Tabs Export

Export all open Safari tabs to a markdown file with AI-generated summaries — via a Python CLI or a native Safari extension.

## TabDown Safari Extension

A native Safari Web Extension that saves all open tabs to a markdown file directly from the toolbar. Includes optional AI summaries via Apple Intelligence (on-device).

### Prerequisites

- **macOS 26+** with Apple Intelligence enabled
- **Xcode 26.3+** (includes the macOS 26 SDK)
- An Apple Developer account signed in to Xcode (free account works for local development)

### Building and Running in Development

1. **Open the project in Xcode:**

   ```bash
   open TabDown/TabDown.xcodeproj
   ```

2. **Select the macOS scheme:**

   In the scheme selector (top-left of the Xcode toolbar), choose **TabDown (macOS)**.

3. **Configure signing:**

   Select the **TabDown (macOS)** target in the project navigator, go to **Signing & Capabilities**, and select your development team. Do the same for the **TabDown Extension (macOS)** target.

   Xcode will automatically create provisioning profiles for both the app (`com.jcmultimedia.TabDown`) and the extension (`com.jcmultimedia.TabDown.Extension`).

4. **Build and run** (⌘R):

   This launches the TabDown companion app. On first run you'll see the extension status and a settings panel.

5. **Enable the extension in Safari:**

   - Open **Safari > Settings > Extensions** (⌘,)
   - Find **TabDown** in the list and check the box to enable it
   - Grant the requested permissions when prompted

   Alternatively, click the **"Quit and Open Safari Settings…"** button in the companion app — it opens the Extensions pane directly.

6. **Allow unsigned extensions (required each Safari launch):**

   Since the extension is locally built and not distributed through the App Store, Safari requires you to re-enable developer extensions each time it starts:

   - Open **Safari > Settings > Advanced**
   - Check **"Show features for web developers"**
   - In the **Develop** menu, check **"Allow unsigned extensions"**

   Safari will prompt for your password. This setting resets every time Safari quits.

### First-Run Setup

After enabling the extension and clicking the TabDown toolbar icon:

1. **Select an output folder:** The popup will show "No output folder configured." Open the TabDown companion app (⌘R from Xcode, or find it in `/Users/you/Library/Developer/Xcode/DerivedData/`), then click **"Choose Folder…"** to pick where markdown files should be saved.

2. **Configure excluded URLs (optional):** In the companion app, scroll to the **Excluded URL Patterns** section. Add host/path prefixes to exclude from exports (e.g. `mail.google.com`, `github.com/notifications`).

3. **Save tabs:** Click the TabDown icon in the Safari toolbar, then **"Save Tabs"**. The markdown file is written to your selected folder with the filename `YYYY-MM-DD HH-MM-SS-saved-tabs.md`.

### Extension Features

- **Save all tabs** across all Safari windows to a single markdown file
- **Deduplication** — strips URL fragments and removes duplicate entries
- **Alphabetical sorting** — tabs sorted by host + path
- **Excluded URL patterns** — filter out tabs matching host/path prefixes (e.g. `mail.google.com`)
- **Close tabs after saving** — checkbox option with confirmation dialog; keeps the active tab open
- **AI summaries** — checkbox option to include Apple Intelligence summaries per tab (extracts page content, summarizes on-device)

### Debugging

**Extension console logs:**

- Open **Develop > Web Extension Background Content** to see `background.js` logs
- Right-click the extension popup and choose **Inspect Element** to see `popup.js` logs

**Native handler logs:**

- `os_log` output appears in Console.app — filter by process `TabDown Extension` or subsystem `com.jcmultimedia.TabDown.Extension`

**Common issues:**

| Problem | Solution |
|---------|----------|
| Extension doesn't appear in Safari | Check that both targets built successfully; re-enable in Safari > Settings > Extensions |
| "Allow unsigned extensions" keeps resetting | This is expected — Safari requires this on every launch for locally-built extensions |
| "No output folder configured" | Open the companion app and click "Choose Folder…" |
| Summarization doesn't work | Verify Apple Intelligence is enabled in System Settings > Apple Intelligence & Siri |
| Tabs aren't closing | The active tab is intentionally excluded; also check that the "Close tabs" checkbox is enabled |
| Build fails with provisioning errors | Run `xcodebuild ... -allowProvisioningUpdates` from the CLI, or select your team in Xcode signing settings |

### Building from the Command Line

```bash
# Debug build
xcodebuild -project TabDown/TabDown.xcodeproj \
  -scheme "TabDown (macOS)" \
  -configuration Debug \
  build -allowProvisioningUpdates

# The built app is in DerivedData:
open ~/Library/Developer/Xcode/DerivedData/TabDown-*/Build/Products/Debug/TabDown.app
```

### Project Structure

```
TabDown/
├── Shared (App)/                    # Companion app (shared iOS/macOS)
│   ├── ViewController.swift         # Folder picker, excluded URL management
│   └── Resources/
│       ├── Base.lproj/Main.html     # App UI
│       ├── Script.js                # App UI logic
│       └── Style.css
├── Shared (Extension)/              # Safari extension (shared iOS/macOS)
│   ├── SafariWebExtensionHandler.swift  # Native message dispatch
│   ├── TabExporter.swift            # Markdown generation, dedup, sort, filter
│   ├── BookmarkAccess.swift         # Security-scoped bookmark for output folder
│   ├── Summarizer.swift             # Apple Intelligence wrapper
│   └── Resources/
│       ├── manifest.json            # MV3 extension manifest
│       ├── popup.html/js/css        # Extension popup UI
│       ├── background.js            # Summarization orchestration
│       ├── extract-content.js       # Content extraction (injected into tabs)
│       └── _locales/en/messages.json
├── macOS (App)/
│   ├── AppDelegate.swift
│   └── TabDown.entitlements         # Sandbox, bookmarks, App Group
├── macOS (Extension)/
│   ├── Info.plist
│   └── TabDownExtension.entitlements  # Sandbox, bookmarks, App Group
└── TabDown.xcodeproj/
```

---

## Python CLI (`export_tabs.py`)

A standalone Python script for exporting tabs from the command line.

### Prerequisites

- macOS 26+ with Apple Intelligence enabled
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- Safari JavaScript from Apple Events enabled:
  1. Safari > Settings > Advanced > **Show features for web developers**
  2. Develop menu > **Allow JavaScript from Apple Events**

### Usage

```bash
# Export to a file
uv run --script export_tabs.py ~/Desktop/tabs.md

# Export to a directory (creates ~/Desktop/2026-03-09-tabs.md)
uv run --script export_tabs.py ~/Desktop/

# Without AI summaries
uv run --script export_tabs.py ~/Desktop/tabs.md --no-summarize

# Close tabs after export
uv run --script export_tabs.py ~/Desktop/tabs.md --close-tabs
```

### Domain Ignore List

Filter out tabs from specific domains by creating `~/.config/safari-tabs/ignore-domains.txt`:

```
# Social media
twitter.com
facebook.com

# Other
reddit.com
```

One domain per line, `#` comments and blank lines are ignored. Subdomains match automatically.

Override with `--ignore-file`:

```bash
uv run --script export_tabs.py ~/Desktop/tabs.md --ignore-file ~/my-ignore-list.txt
```

### Daily Scheduling

```bash
# Install (runs daily at 9:00 AM by default)
uv run --script export_tabs.py --install-schedule

# Custom hour and output directory
uv run --script export_tabs.py --install-schedule --schedule-hour 18 --schedule-output-dir ~/Dropbox/tabs

# Remove the schedule
uv run --script export_tabs.py --uninstall-schedule
```

- **Plist:** `~/Library/LaunchAgents/com.user.safari-tabs-export.plist`
- **Logs:** `~/Library/Logs/safari-tabs-export.log`
- **Default output:** `~/Documents/safari-tabs/`

### Output Format

```markdown
# Safari Tabs Export

**Date:** 2026-03-09
**Total tabs:** 58 | **Unique:** 53 | **Duplicates removed:** 5
**Windows:** 2

---

- [Example Page](https://example.com)
  > AI-generated summary of the content...
```
