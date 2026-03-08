#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["anthropic"]
# ///
"""Export all open Safari tabs to a markdown file with AI-generated summaries."""

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from urllib.parse import urldefrag

# ---------------------------------------------------------------------------
# JXA scripts
# ---------------------------------------------------------------------------

JXA_GET_TABS = """
(() => {
    const safari = Application("Safari");
    if (!safari.running()) return JSON.stringify({error: "Safari is not running"});
    const results = [];
    const windows = safari.windows();
    for (let w = 0; w < windows.length; w++) {
        const tabs = windows[w].tabs();
        for (let t = 0; t < tabs.length; t++) {
            const tab = tabs[t];
            const url = tab.url() || "";
            const title = tab.name() || "";
            if (url && !url.startsWith("favorites://") && url !== "") {
                results.push({window: w + 1, tab_index: t + 1, url: url, title: title});
            }
        }
    }
    return JSON.stringify(results);
})();
"""

JXA_GET_TEXT_TEMPLATE = """
(() => {{
    const safari = Application("Safari");
    const tab = safari.windows()[{window}].tabs()[{tab}];
    return safari.doJavaScript("document.body.innerText.substring(0, 2000)", {{in: tab}});
}})();
"""

# ---------------------------------------------------------------------------
# Tab extraction
# ---------------------------------------------------------------------------


def run_jxa(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def get_tabs() -> list[dict]:
    raw = run_jxa(JXA_GET_TABS)
    data = json.loads(raw)
    if isinstance(data, dict) and "error" in data:
        print(f"Error: {data['error']}", file=sys.stderr)
        sys.exit(1)
    return data


def get_tab_text(tab: dict) -> str | None:
    """Extract page text for a single tab. Returns None on failure."""
    script = JXA_GET_TEXT_TEMPLATE.format(
        window=tab["window"] - 1, tab=tab["tab_index"] - 1
    )
    try:
        return run_jxa(script)
    except Exception as e:
        err = str(e)
        if "not allowed" in err.lower() or "permission" in err.lower():
            print(
                "Warning: JavaScript from Apple Events is not enabled.\n"
                "  Enable it in Safari > Settings > Advanced > 'Show features for web developers',\n"
                "  then Developer > 'Allow JavaScript from Apple Events'.\n"
                "  Falling back to title-only mode.",
                file=sys.stderr,
            )
        return None


# ---------------------------------------------------------------------------
# Summarization
# ---------------------------------------------------------------------------

_permission_warned = False


def extract_texts(tabs: list[dict]) -> dict[str, str]:
    """Extract page text for all tabs. Returns {url: text}."""
    global _permission_warned
    texts: dict[str, str] = {}
    for tab in tabs:
        if _permission_warned:
            break
        text = get_tab_text(tab)
        if text is None:
            _permission_warned = True
        else:
            texts[tab["url"]] = text
    return texts


def fallback_summary(text: str | None) -> str:
    """Return first ~2 sentences of raw text as fallback."""
    if not text:
        return ""
    sentences = []
    current = []
    for char in text[:500]:
        current.append(char)
        if char in ".!?" and len("".join(current).strip()) > 10:
            sentences.append("".join(current).strip())
            current = []
            if len(sentences) >= 2:
                break
    if current and len(sentences) < 2:
        sentences.append("".join(current).strip())
    return " ".join(sentences)


async def _summarize_with_apple(texts: dict[str, str]) -> dict[str, str]:
    """Summarize page texts using Apple Intelligence on-device model."""
    import apple_fm_sdk as fm

    model = fm.SystemLanguageModel()
    is_available, reason = model.is_available()
    if not is_available:
        raise RuntimeError(f"Apple Intelligence not available: {reason}")

    summaries: dict[str, str] = {}
    for i, (url, text) in enumerate(texts.items(), 1):
        print(f"  Summarizing {i}/{len(texts)}...", file=sys.stderr)
        session = fm.LanguageModelSession(
            instructions="Summarize web page content in 1-2 concise sentences.",
            model=model,
        )
        try:
            response = await session.respond(text)
            summaries[url] = str(response)
        except (fm.ExceededContextWindowSizeError, fm.GuardrailViolationError, fm.GenerationError):
            summaries[url] = fallback_summary(text)
    return summaries


def summarize_with_apple(texts: dict[str, str]) -> dict[str, str]:
    """Sync wrapper for Apple Intelligence summarization."""
    import asyncio
    return asyncio.run(_summarize_with_apple(texts))


def summarize_with_claude(texts: dict[str, str]) -> dict[str, str]:
    """Summarize page texts using Claude. Returns {url: summary}."""
    try:
        import anthropic
    except ImportError:
        print("Warning: anthropic package not installed. Skipping AI summaries.", file=sys.stderr)
        return {url: fallback_summary(text) for url, text in texts.items()}

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Warning: ANTHROPIC_API_KEY not set. Using text excerpts instead.", file=sys.stderr)
        return {url: fallback_summary(text) for url, text in texts.items()}

    client = anthropic.Anthropic(api_key=api_key)
    summaries: dict[str, str] = {}

    def _summarize_one(url: str, text: str) -> tuple[str, str]:
        try:
            response = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=150,
                messages=[
                    {
                        "role": "user",
                        "content": f"Summarize this web page content in 1-2 concise sentences:\n\n{text}",
                    }
                ],
            )
            return url, response.content[0].text
        except Exception:
            return url, fallback_summary(text)

    with ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(_summarize_one, url, text): url for url, text in texts.items()}
        for future in as_completed(futures):
            url, summary = future.result()
            summaries[url] = summary

    return summaries


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------


def deduplicate(tabs: list[dict]) -> tuple[list[dict], int]:
    """Deduplicate tabs by URL (stripping fragments). Returns (unique_tabs, dup_count)."""
    seen: dict[str, dict] = {}
    for tab in tabs:
        key = urldefrag(tab["url"])[0]
        if key not in seen:
            seen[key] = tab
    dup_count = len(tabs) - len(seen)
    return list(seen.values()), dup_count


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------


def render_markdown(
    tabs: list[dict],
    summaries: dict[str, str],
    total_count: int,
    dup_count: int,
    num_windows: int,
    group_by_window: bool,
) -> str:
    lines = [
        "# Safari Tabs Export",
        "",
        f"**Date:** {date.today().isoformat()}",
        f"**Total tabs:** {total_count} | **Unique:** {len(tabs)} | **Duplicates removed:** {dup_count}",
        f"**Windows:** {num_windows}",
        "",
        "---",
        "",
    ]

    def _render_tab(tab: dict) -> list[str]:
        title = tab["title"] or tab["url"]
        entry = [f"- [{title}]({tab['url']})"]
        summary = summaries.get(tab["url"], "")
        if summary:
            entry.append(f"  > {summary}")
        return entry

    if group_by_window:
        from itertools import groupby

        for window_num, group in groupby(tabs, key=lambda t: t["window"]):
            group_tabs = list(group)
            lines.append(f"## Window {window_num} ({len(group_tabs)} tabs)")
            lines.append("")
            for tab in group_tabs:
                lines.extend(_render_tab(tab))
            lines.append("")
    else:
        for tab in tabs:
            lines.extend(_render_tab(tab))
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Export Safari tabs to markdown.")
    parser.add_argument("output_path", help="File path or directory to save the markdown file (directory uses DATE-tabs.md)")
    parser.add_argument("--no-summarize", action="store_true", help="Skip AI summaries")
    parser.add_argument(
        "--backend",
        choices=["auto", "apple", "claude"],
        default="auto",
        help="Summarization backend: auto (try Apple then Claude), apple, or claude (default: auto)",
    )
    parser.add_argument(
        "--group-by-window", action="store_true", help="Group tabs by Safari window"
    )
    args = parser.parse_args()

    # Phase 1: Extract
    print("Extracting tabs from Safari...", file=sys.stderr)
    tabs = get_tabs()
    if not tabs:
        print("No tabs found in Safari.", file=sys.stderr)
        sys.exit(0)

    total_count = len(tabs)
    num_windows = len({t["window"] for t in tabs})

    # Phase 2: Deduplicate
    tabs, dup_count = deduplicate(tabs)

    # Phase 3: Summarize
    summaries: dict[str, str] = {}
    if not args.no_summarize:
        print("Extracting page text...", file=sys.stderr)
        texts = extract_texts(tabs)
        if texts:
            print(f"Summarizing {len(texts)} pages...", file=sys.stderr)
            backend = args.backend

            if backend == "apple":
                try:
                    summaries = summarize_with_apple(texts)
                except (ImportError, RuntimeError) as e:
                    print(f"Error: {e}", file=sys.stderr)
                    sys.exit(1)
            elif backend == "claude":
                summaries = summarize_with_claude(texts)
            else:  # auto
                try:
                    summaries = summarize_with_apple(texts)
                    print("Using Apple Intelligence for summaries.", file=sys.stderr)
                except (ImportError, RuntimeError):
                    print("Apple Intelligence not available, falling back to Claude.", file=sys.stderr)
                    summaries = summarize_with_claude(texts)
    else:
        print("Skipping summaries (--no-summarize).", file=sys.stderr)

    # Phase 4: Render
    md = render_markdown(tabs, summaries, total_count, dup_count, num_windows, args.group_by_window)

    output_path = os.path.expanduser(args.output_path)
    if os.path.isdir(output_path):
        output_path = os.path.join(output_path, f"{date.today().isoformat()}-tabs.md")
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        f.write(md)

    print(f"Exported {len(tabs)} tabs to {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
