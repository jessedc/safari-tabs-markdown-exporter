#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest", "apple-fm-sdk"]
# ///
"""Integration tests verifying Apple Intelligence summarization works end-to-end."""

import importlib
import sys

import apple_fm_sdk as fm
import pytest

# ---------------------------------------------------------------------------
# Skip everything if Apple Intelligence isn't available on this machine
# ---------------------------------------------------------------------------

_model = fm.SystemLanguageModel()
_available, _reason = _model.is_available()
pytestmark = pytest.mark.skipif(
    not _available,
    reason=f"Apple Intelligence not available: {_reason}",
)

# ---------------------------------------------------------------------------
# Realistic page texts from currently open Safari tabs
# ---------------------------------------------------------------------------

THREAD_TEXT = (
    "What is Thread?\n\n"
    "Thread is an IPv6-based networking protocol designed for low-power "
    "Internet of Things devices. It is a mesh networking protocol that "
    "provides secure, reliable device-to-device and device-to-cloud "
    "communication. Thread networks have no single point of failure, "
    "can self-heal, and support seamless integration with existing IP "
    "infrastructure. The Thread Group manages the specification and "
    "promotes interoperability among Thread-certified products."
)

FM_SDK_TEXT = (
    "Basic Usage — Foundation Models SDK for Python\n\n"
    "The Foundation Models framework lets you integrate Apple Intelligence "
    "language models directly into your app. You can generate text, "
    "summarize content, and extract structured data using on-device models "
    "that run privately. To get started, import apple_fm_sdk and create a "
    "SystemLanguageModel instance. Check availability with is_available(), "
    "then create a LanguageModelSession with your instructions. Call "
    "session.respond() with your prompt to generate a response."
)

AWTRIX_TEXT = (
    "AWTRIX 3\n\n"
    "AWTRIX 3 is a custom firmware for the Ulanzi TC001 pixel clock. "
    "It transforms the affordable hardware into a powerful smart display "
    "that integrates with Home Assistant, MQTT, and HTTP APIs. Display "
    "notifications, custom apps, weather data, sensor readings, and more "
    "on the 32x8 LED matrix. AWTRIX 3 supports OTA updates, custom "
    "animations, and has a built-in icon manager."
)

HOMEKIT_TEXT = (
    "HomeKit | Apple Developer Documentation\n\n"
    "HomeKit enables your app to coordinate and control home automation "
    "accessories from multiple vendors to present them coherently under "
    "a single interface. Using HomeKit, your app can discover accessories "
    "in the user's home, configure them, create actions to control those "
    "accessories, group actions together into triggers, and fire them via "
    "Siri voice commands or automations."
)

MATTER_TEXT = (
    "Matter - Home Assistant\n\n"
    "The Matter integration allows you to control Matter devices in Home "
    "Assistant. Matter is a connectivity standard for smart home devices "
    "that provides local control, reliability, and interoperability across "
    "ecosystems. Devices commissioned with Matter can be shared across "
    "multiple platforms simultaneously, such as Apple Home, Google Home, "
    "and Amazon Alexa, while still being controlled locally through Home "
    "Assistant."
)

REALISTIC_TABS = {
    "https://openthread.io/guides/thread-primer/index.md": THREAD_TEXT,
    "https://apple.github.io/python-apple-fm-sdk/basic_usage.html": FM_SDK_TEXT,
    "https://blueforcer.github.io/awtrix3/#/README": AWTRIX_TEXT,
    "https://developer.apple.com/documentation/homekit": HOMEKIT_TEXT,
    "https://www.home-assistant.io/integrations/matter": MATTER_TEXT,
}


def _import_export_tabs():
    if "export_tabs" in sys.modules:
        return importlib.reload(sys.modules["export_tabs"])
    import export_tabs
    return export_tabs


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestAppleSummarizationIntegration:
    def test_single_page_returns_nonempty_summary(self):
        mod = _import_export_tabs()
        texts = {"https://openthread.io/guides/thread-primer/index.md": THREAD_TEXT}

        result = mod.summarize(texts)

        assert len(result) == 1
        summary = result["https://openthread.io/guides/thread-primer/index.md"]
        assert isinstance(summary, str)
        assert len(summary) > 10, f"Summary too short: {summary!r}"

    def test_summary_is_shorter_than_input(self):
        mod = _import_export_tabs()
        texts = {"https://developer.apple.com/documentation/homekit": HOMEKIT_TEXT}

        result = mod.summarize(texts)

        summary = result["https://developer.apple.com/documentation/homekit"]
        assert len(summary) < len(HOMEKIT_TEXT), "Summary should be shorter than the input"

    def test_summary_is_relevant_to_input(self):
        """The summary of the Thread page should mention networking/IoT concepts."""
        mod = _import_export_tabs()
        texts = {"https://openthread.io/guides/thread-primer/index.md": THREAD_TEXT}

        result = mod.summarize(texts)

        summary = result["https://openthread.io/guides/thread-primer/index.md"].lower()
        relevant_terms = ["thread", "network", "iot", "mesh", "device", "protocol", "ipv6"]
        assert any(term in summary for term in relevant_terms), (
            f"Summary doesn't seem relevant to Thread: {summary!r}"
        )

    def test_multiple_pages_all_summarized(self):
        mod = _import_export_tabs()

        result = mod.summarize(REALISTIC_TABS)

        assert set(result.keys()) == set(REALISTIC_TABS.keys())
        for url, summary in result.items():
            assert isinstance(summary, str)
            assert len(summary) > 10, f"Summary for {url} too short: {summary!r}"

    def test_different_pages_get_different_summaries(self):
        mod = _import_export_tabs()
        texts = {
            "https://openthread.io/guides/thread-primer/index.md": THREAD_TEXT,
            "https://blueforcer.github.io/awtrix3/#/README": AWTRIX_TEXT,
        }

        result = mod.summarize(texts)

        thread_summary = result["https://openthread.io/guides/thread-primer/index.md"]
        awtrix_summary = result["https://blueforcer.github.io/awtrix3/#/README"]
        assert thread_summary != awtrix_summary, "Different pages should produce different summaries"

    def test_empty_input_returns_empty(self):
        mod = _import_export_tabs()

        result = mod.summarize({})

        assert result == {}
