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
