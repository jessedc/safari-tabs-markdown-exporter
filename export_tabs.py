#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["apple-fm-sdk"]
# ///
"""Export all open Safari tabs to a markdown file with AI-generated summaries."""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import date
from pathlib import Path
from urllib.parse import urldefrag, urlparse

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

JXA_CLOSE_TABS_TEMPLATE = """
(() => {{
    const safari = Application("Safari");
    const urls = new Set({urls_json});
    const windows = safari.windows();
    for (let w = windows.length - 1; w >= 0; w--) {{
        const tabs = windows[w].tabs();
        for (let t = tabs.length - 1; t >= 0; t--) {{
            const url = tabs[t].url() || "";
            if (urls.has(url)) {{
                tabs[t].close();
            }}
        }}
    }}
    return "ok";
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
# Domain filtering
# ---------------------------------------------------------------------------

IGNORE_DOMAINS_DEFAULT = os.path.expanduser("~/.config/safari-tabs/ignore-domains.txt")


def load_ignore_domains(path: str) -> set[str]:
    """Load ignored domains from file. Returns empty set if file missing."""
    try:
        lines = Path(path).read_text().splitlines()
    except FileNotFoundError:
        return set()
    domains = set()
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#"):
            domains.add(line.lower())
    return domains


def filter_ignored(tabs: list[dict], domains: set[str]) -> list[dict]:
    """Remove tabs whose hostname matches an ignored domain."""
    if not domains:
        return tabs
    result = []
    for tab in tabs:
        hostname = urlparse(tab["url"]).hostname or ""
        hostname = hostname.lower()
        if hostname in domains or any(hostname.endswith("." + d) for d in domains):
            continue
        result.append(tab)
    return result


# ---------------------------------------------------------------------------
# Close tabs
# ---------------------------------------------------------------------------


def close_tabs(tabs: list[dict]) -> None:
    """Close the given tabs in Safari by URL."""
    urls = [tab["url"] for tab in tabs]
    script = JXA_CLOSE_TABS_TEMPLATE.format(urls_json=json.dumps(urls))
    run_jxa(script)


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
) -> str:
    lines = [
        "# Safari Tabs Export",
        "",
        f"**Date:** {date.today().isoformat()}",
        "",
        "---",
        "",
    ]

    # Section 1: links only
    for tab in tabs:
        title = tab["title"] or tab["url"]
        lines.append(f"- [{title}]({tab['url']})")
    lines.append("")

    # Section 2: links with summaries
    summary_lines = []
    for tab in tabs:
        summary = summaries.get(tab["url"], "")
        if summary:
            title = tab["title"] or tab["url"]
            summary_lines.append(f"- [{title}]({tab['url']})")
            summary_lines.append(f"  {summary}")
    if summary_lines:
        lines.append("---")
        lines.append("")
        lines.extend(summary_lines)
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Scheduling (launchd)
# ---------------------------------------------------------------------------

PLIST_LABEL = "com.user.safari-tabs-export"
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{PLIST_LABEL}.plist")
LOG_PATH = os.path.expanduser("~/Library/Logs/safari-tabs-export.log")


def install_schedule(args: argparse.Namespace) -> None:
    """Generate a launchd plist and load it."""
    uv_path = shutil.which("uv")
    if not uv_path:
        print("Error: 'uv' not found in PATH.", file=sys.stderr)
        sys.exit(1)

    script_path = os.path.abspath(__file__)
    output_dir = os.path.expanduser(args.schedule_output_dir)
    os.makedirs(output_dir, exist_ok=True)

    program_args = [uv_path, "run", "--script", script_path, output_dir]
    if args.no_summarize or args.schedule_no_summarize:
        program_args.append("--no-summarize")
    if args.schedule_close_tabs:
        program_args.append("--close-tabs")
    if args.ignore_file:
        program_args.extend(["--ignore-file", args.ignore_file])

    args_xml = "\n        ".join(f"<string>{a}</string>" for a in program_args)
    plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        {args_xml}
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>{args.schedule_hour}</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>{LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>{LOG_PATH}</string>
</dict>
</plist>
"""
    os.makedirs(os.path.dirname(PLIST_PATH), exist_ok=True)
    with open(PLIST_PATH, "w") as f:
        f.write(plist)

    subprocess.run(["launchctl", "load", PLIST_PATH], check=True)
    print(f"Installed schedule: daily at {args.schedule_hour}:00", file=sys.stderr)
    print(f"Plist: {PLIST_PATH}", file=sys.stderr)
    print(f"Output: {output_dir}", file=sys.stderr)
    print(f"Logs: {LOG_PATH}", file=sys.stderr)


def uninstall_schedule() -> None:
    """Unload and remove the launchd plist."""
    if not os.path.exists(PLIST_PATH):
        print("No schedule installed.", file=sys.stderr)
        return
    subprocess.run(["launchctl", "unload", PLIST_PATH], check=True)
    os.remove(PLIST_PATH)
    print("Schedule removed.", file=sys.stderr)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Export Safari tabs to markdown.")
    parser.add_argument("output_path", nargs="?", help="File path or directory to save the markdown file (directory uses DATE-tabs.md)")
    parser.add_argument("--no-summarize", action="store_true", help="Skip AI summaries")
    parser.add_argument("--ignore-file", metavar="PATH", help="Path to domain ignore list (default: ~/.config/safari-tabs/ignore-domains.txt)")
    parser.add_argument("--close-tabs", action="store_true", help="Close exported tabs in Safari after writing")

    # Schedule management
    parser.add_argument("--install-schedule", action="store_true", help="Install daily launchd schedule")
    parser.add_argument("--uninstall-schedule", action="store_true", help="Remove daily launchd schedule")
    parser.add_argument("--schedule-hour", type=int, default=9, metavar="HOUR", help="Hour to run daily export (default: 9)")
    parser.add_argument("--schedule-output-dir", default="~/Documents/safari-tabs", metavar="DIR", help="Output directory for scheduled exports")
    parser.add_argument("--schedule-no-summarize", action="store_true", help="Skip summaries in scheduled runs")
    parser.add_argument("--schedule-close-tabs", action="store_true", help="Close tabs in scheduled runs")
    args = parser.parse_args()

    # Handle schedule commands (early exit)
    if args.uninstall_schedule:
        uninstall_schedule()
        return
    if args.install_schedule:
        install_schedule(args)
        return

    if not args.output_path:
        parser.error("output_path is required (unless using --install-schedule or --uninstall-schedule)")

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

    # Phase 3: Filter ignored domains
    ignore_path = args.ignore_file or IGNORE_DOMAINS_DEFAULT
    if args.ignore_file and not os.path.exists(ignore_path):
        print(f"Warning: ignore file not found: {ignore_path}", file=sys.stderr)
    ignore_domains = load_ignore_domains(ignore_path)
    tabs = filter_ignored(tabs, ignore_domains)

    # Phase 4: Summarize
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

    # Phase 5: Render
    md = render_markdown(tabs, summaries, texts, total_count, dup_count, num_windows)

    output_path = os.path.expanduser(args.output_path)
    if os.path.isdir(output_path):
        output_path = os.path.join(output_path, f"{date.today().isoformat()}-tabs.md")
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        f.write(md)

    print(f"Exported {len(tabs)} tabs to {output_path}", file=sys.stderr)

    # Phase 6: Close tabs
    if args.close_tabs and tabs:
        if sys.stdin.isatty():
            answer = input(f"Close {len(tabs)} tabs in Safari? [y/N] ")
            if answer.strip().lower() != "y":
                return
        print("Closing tabs in Safari...", file=sys.stderr)
        close_tabs(tabs)
        print(f"Closed {len(tabs)} tabs.", file=sys.stderr)


if __name__ == "__main__":
    main()
