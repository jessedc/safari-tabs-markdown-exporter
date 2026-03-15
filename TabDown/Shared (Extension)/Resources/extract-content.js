// Content extraction script — injected into tabs via browser.scripting.executeScript
// Uses document.body.innerText as the extraction method.
// Readability can be bundled here in the future for better extraction.
(function() {
    try {
        const text = document.body?.innerText || "";
        const truncated = text.substring(0, 10000);
        console.log(`[extract-content] extracted ${text.length} chars, truncated to ${truncated.length} from ${document.location.href}`);
        return truncated;
    } catch (e) {
        console.error("[extract-content] extraction failed:", e.message);
        return "";
    }
})();
