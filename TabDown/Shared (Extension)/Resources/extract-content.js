// Content extraction script — injected into tabs via browser.scripting.executeScript
// Uses document.body.innerText as the extraction method.
// Readability can be bundled here in the future for better extraction.
(function() {
    try {
        const text = document.body?.innerText || "";
        // Truncate to 10,000 characters
        return text.substring(0, 10000);
    } catch (e) {
        return "";
    }
})();
