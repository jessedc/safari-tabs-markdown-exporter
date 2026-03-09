#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["apple-fm-sdk"]
# ///
"""Export all open Safari tabs to a markdown file with AI-generated summaries."""

import argparse
import json
import os
import subprocess
import sys
import time
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

JXA_RELOAD_TAB_TEMPLATE = """
(() => {{
    const safari = Application("Safari");
    const tab = safari.windows()[{window}].tabs()[{tab}];
    const url = tab.url();
    tab.url = url;
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


def get_tab_text(tab: dict, reload_delay: int = 3) -> tuple[str | None, bool]:
    """Extract page text for a single tab, reloading if suspended.

    Returns (text, was_reloaded). text is None on failure.
    """
    window = tab["window"] - 1
    tab_idx = tab["tab_index"] - 1
    script = JXA_GET_TEXT_TEMPLATE.format(window=window, tab=tab_idx)
    try:
        text = run_jxa(script)
        if text and len(text) >= 50:
            return text, False
        # Tab likely suspended — reload and retry
        reload_script = JXA_RELOAD_TAB_TEMPLATE.format(window=window, tab=tab_idx)
        run_jxa(reload_script)
        time.sleep(reload_delay)
        retried = run_jxa(script)
        return retried if retried else "", True
    except Exception:
        return None, False


# ---------------------------------------------------------------------------
# Summarization
# ---------------------------------------------------------------------------


def extract_texts(tabs: list[dict]) -> dict[str, str]:
    """Extract page text for all tabs. Exits with instructions if JS permission is missing."""
    texts: dict[str, str] = {}
    for i, tab in enumerate(tabs, 1):
        text, reloaded = get_tab_text(tab)
        if reloaded:
            print(f"  Tab {i}/{len(tabs)}: reloading suspended tab...", file=sys.stderr)
        if text is None:
            print(
                "Error: Cannot extract page content — JavaScript from Apple Events is not enabled.\n"
                "\n"
                "To enable it:\n"
                "  1. Open Safari > Settings > Advanced\n"
                '  2. Check "Show features for web developers"\n'
                "  3. Close Settings, then go to the Develop menu\n"
                '  4. Check "Allow JavaScript from Apple Events"\n'
                "\n"
                "Then re-run this script.",
                file=sys.stderr,
            )
            sys.exit(1)
        texts[tab["url"]] = text
    return texts


_REFUSAL_PREFIXES = (
    "i apologize",
    "i'm sorry",
    "sorry",
    "i cannot",
    "i can't",
    "i'm unable",
    "sure, i'd be happy to help",
)


def _is_refusal(text: str) -> bool:
    """Detect model refusal/apology responses that aren't useful summaries."""
    lower = text.strip().lower()
    return any(lower.startswith(p) for p in _REFUSAL_PREFIXES)


def _is_useless_summary(response: str, input_text: str) -> bool:
    """Detect responses that just echo the title back or are refusals."""
    if _is_refusal(response):
        return True
    # Model echoed the input verbatim or said "summary unavailable"
    if response.strip().lower() in (input_text.strip().lower(), "summary unavailable"):
        return True
    return False


async def _summarize(texts: dict[str, str]) -> dict[str, str]:
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
            instructions=(
                "Summarize the following content in 1-2 concise sentences. "
                "Write only the summary — do not start with 'This page', 'The page', "
                "'A webpage', 'This web page', or similar references to it being a page. "
                "Do not repeat the title. Do not apologize or refuse. "
                "If the content is insufficient (e.g. just a title, a login page, "
                "or a generic page name), explain briefly why a summary isn't possible, "
                "e.g. 'Title only — no content available' or 'Login page — no "
                "summarizable content'."
            ),
            model=model,
        )
        try:
            response = str(await session.respond(text))
            if _is_useless_summary(response, text):
                summaries[url] = "Could not summarize — insufficient content"
            else:
                # Strip preamble like "Summary:" that the model sometimes adds
                cleaned = response.strip()
                if cleaned.lower().startswith("summary:"):
                    cleaned = cleaned[len("summary:"):].strip()
                summaries[url] = cleaned
        except fm.ExceededContextWindowSizeError:
            summaries[url] = "Could not summarize — content too long for on-device model"
        except fm.GuardrailViolationError:
            summaries[url] = "Could not summarize — content blocked by safety filter"
        except fm.GenerationError as e:
            summaries[url] = f"Could not summarize — generation failed: {e}"
    return summaries


def summarize(texts: dict[str, str]) -> dict[str, str]:
    """Summarize page texts using Apple Intelligence."""
    import asyncio
    return asyncio.run(_summarize(texts))


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
    texts: dict[str, str],
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
    texts: dict[str, str] = {}
    if not args.no_summarize:
        print("Extracting page text...", file=sys.stderr)
        texts = extract_texts(tabs)
        if texts:
            print(f"Summarizing {len(texts)} pages with Apple Intelligence...", file=sys.stderr)
            try:
                summaries = summarize(texts)
            except (ImportError, RuntimeError) as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)
    else:
        print("Skipping summaries (--no-summarize).", file=sys.stderr)

    # Phase 4: Render
    md = render_markdown(tabs, summaries, texts, total_count, dup_count, num_windows, args.group_by_window)

    output_path = os.path.expanduser(args.output_path)
    if os.path.isdir(output_path):
        output_path = os.path.join(output_path, f"{date.today().isoformat()}-tabs.md")
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        f.write(md)

    print(f"Exported {len(tabs)} tabs to {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
