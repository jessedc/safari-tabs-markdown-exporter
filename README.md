# Safari Tabs Export

Export all open Safari tabs to a markdown file with AI-generated summaries, deduplication, and statistics.

## Prerequisites

- macOS with Safari
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- Safari JavaScript from Apple Events enabled:
  1. Safari > Settings > Advanced > **Show features for web developers**
  2. Develop menu > **Allow JavaScript from Apple Events**

## Usage

```bash
# Basic export
uv run export_tabs.py ~/Desktop/tabs.md

# Export to a directory (creates ~/Desktop/2026-03-08-tabs.md)
uv run export_tabs.py ~/Desktop/

# Without AI summaries
uv run export_tabs.py ~/Desktop/tabs.md --no-summarize

# Group tabs by window
uv run export_tabs.py ~/Desktop/tabs.md --group-by-window
```

For AI summaries, set your Anthropic API key:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
uv run export_tabs.py ~/Desktop/tabs.md
```

Without the API key, the script falls back to text excerpts from each page.

## Output

The script generates a markdown file like:

```markdown
# Safari Tabs Export

**Date:** 2026-03-08
**Total tabs:** 24 | **Unique:** 21 | **Duplicates removed:** 3
**Windows:** 2

---

- [Example Page](https://example.com)
  > AI-generated summary of this page's content...
```
