browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("[background] received message:", request.action, "from:", sender?.url || "popup");
    if (request.action === "startSummarization") {
        console.log("[background] starting summarization for", request.tabs.length, "tabs");
        handleSummarization(request.tabs);
    }
});

async function handleSummarization(tabs) {
    const tabsWithSummaries = [];

    for (let i = 0; i < tabs.length; i++) {
        const tab = tabs[i];
        console.log(`[background] processing tab ${i + 1}/${tabs.length}: "${tab.title}" (${tab.url})`);

        // Notify popup of progress
        browser.runtime.sendMessage({
            action: "summarizeProgress",
            current: i + 1,
            total: tabs.length
        }).catch(() => {});

        let summary = "";
        try {
            // Extract content from the tab
            console.log(`[background] injecting extract-content.js into tab ${tab.id}`);
            const results = await browser.scripting.executeScript({
                target: { tabId: tab.id },
                files: ["Readability.js", "extract-content.js"]
            });

            const content = results?.[results.length - 1]?.result || "";
            console.log(`[background] extracted content from tab ${tab.id}: ${content.length} chars`);

            if (content && content.length > 10) {
                console.log(`[background] requesting summary from native app for tab ${tab.id}`);
                const response = await browser.runtime.sendNativeMessage(
                    "application.id",
                    { action: "summarize", text: content, title: tab.title, url: tab.url }
                );
                console.log(`[background] summarize response for tab ${tab.id}:`, response.success, response.summary?.substring(0, 80));
                if (response.success) {
                    summary = response.summary;
                } else {
                    console.warn(`[background] summarize failed for tab ${tab.id}:`, response.error);
                }
            } else {
                console.warn(`[background] skipping summary for tab ${tab.id}: content too short (${content.length} chars)`);
            }
        } catch (err) {
            console.warn(`[background] error processing tab ${tab.id} ("${tab.title}"):`, err.message);
        }

        tabsWithSummaries.push({
            url: tab.url,
            title: tab.title,
            summary: summary
        });
    }

    // Save the tabs with summaries
    console.log("[background] all tabs processed, sending saveTabs to native app");
    try {
        const response = await browser.runtime.sendNativeMessage(
            "application.id",
            { action: "saveTabs", tabs: tabsWithSummaries }
        );
        console.log("[background] saveTabs response:", response);

        browser.runtime.sendMessage({
            action: "summarizeComplete",
            success: response.success,
            filePath: response.filePath,
            error: response.error,
            tabs: tabs
        }).catch(() => {});
    } catch (err) {
        console.error("[background] saveTabs failed:", err.message);
        browser.runtime.sendMessage({
            action: "summarizeComplete",
            success: false,
            error: err.message,
            tabs: tabs
        }).catch(() => {});
    }
}
