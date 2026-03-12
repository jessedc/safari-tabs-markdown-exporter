# Safari Tabs Export

Export all open Safari tabs to a markdown file with AI-generated summaries.

## Features

- Exports all open Safari tabs across all windows
- Summarizes each tab using Apple Intelligence (on-device, free, no API key)
- Deduplicates tabs by URL (stripping fragments)
- Automatically reloads suspended/purged tabs to extract content
- Outputs clean markdown with tab titles, links, and summaries

## Prerequisites

- macOS 26+ with Apple Intelligence enabled
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- Safari JavaScript from Apple Events enabled:
  1. Safari > Settings > Advanced > **Show features for web developers**
  2. Develop menu > **Allow JavaScript from Apple Events**

## Usage

```bash
# Export to a file
uv run --script export_tabs.py ~/Desktop/tabs.md

# Export to a directory (creates ~/Desktop/2026-03-09-tabs.md)
uv run --script export_tabs.py ~/Desktop/

# Without AI summaries
uv run --script export_tabs.py ~/Desktop/tabs.md --no-summarize

```

## Domain Ignore List

Filter out tabs from specific domains by creating a file at `~/.config/safari-tabs/ignore-domains.txt`:

```
# Social media
twitter.com
facebook.com

# Other
reddit.com
```

One domain per line, `#` comments and blank lines are ignored. Subdomains are matched automatically (e.g. `twitter.com` also filters `mobile.twitter.com`).

Override the file path with `--ignore-file`:

```bash
uv run --script export_tabs.py ~/Desktop/tabs.md --ignore-file ~/my-ignore-list.txt
```

## Closing Tabs

Use `--close-tabs` to close exported tabs in Safari after writing the file:

```bash
uv run --script export_tabs.py ~/Desktop/tabs.md --close-tabs
```

When running interactively, you'll be prompted to confirm. In non-interactive mode (e.g. launchd), tabs are closed without prompting.

## Daily Scheduling

Install a daily launchd schedule to automatically export tabs:

```bash
# Install (runs daily at 9:00 AM by default)
uv run --script export_tabs.py --install-schedule

# Custom hour and output directory
uv run --script export_tabs.py --install-schedule --schedule-hour 18 --schedule-output-dir ~/Dropbox/tabs

# Include tab closing and skip summaries in scheduled runs
uv run --script export_tabs.py --install-schedule --schedule-close-tabs --schedule-no-summarize

# Remove the schedule
uv run --script export_tabs.py --uninstall-schedule
```

- **Plist:** `~/Library/LaunchAgents/com.user.safari-tabs-export.plist`
- **Logs:** `~/Library/Logs/safari-tabs-export.log`
- **Default output:** `~/Documents/safari-tabs/`

Check if the schedule is active:

```bash
launchctl list | grep safari-tabs
```

## Output

The script generates a markdown file like:

```markdown
# Safari Tabs Export

**Date:** 2026-03-09
**Total tabs:** 58 | **Unique:** 53 | **Duplicates removed:** 5
**Windows:** 2

---

- [Example Page](https://example.com)
  > AI-generated summary of the content...
```
