// Content extraction script — injected into tabs via browser.scripting.executeScript
// Uses Mozilla Readability for article extraction with innerText fallback.
(function() {
    try {
        const documentClone = document.cloneNode(true);
        const reader = new Readability(documentClone);
        const article = reader.parse();
        const raw = article?.textContent || "";
        // Collapse whitespace: trim each line, drop blank lines, normalize spaces
        const text = raw
            .split("\n")
            .map(l => l.trim())
            .filter(l => l.length > 0)
            .join("\n")
            .replace(/ {2,}/g, " ");
        const truncated = text.substring(0, 10000);
        console.log(`[extract-content] extracted ${text.length} chars (readability: ${!!article?.textContent}), truncated to ${truncated.length}`);
        return truncated;
    } catch (e) {
        console.error("[extract-content] extraction failed:", e.message);
        return "";
    }
})();
