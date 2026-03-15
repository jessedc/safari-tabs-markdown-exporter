browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "startSummarization") {
        handleSummarization(request.tabs);
    }
});

async function handleSummarization(tabs) {
    const tabsWithSummaries = [];

    for (let i = 0; i < tabs.length; i++) {
        const tab = tabs[i];

        // Notify popup of progress
        browser.runtime.sendMessage({
            action: "summarizeProgress",
            current: i + 1,
            total: tabs.length
        }).catch(() => {});

        let summary = "";
        try {
            // Extract content from the tab
            const results = await browser.scripting.executeScript({
                target: { tabId: tab.id },
                files: ["extract-content.js"]
            });

            const content = results?.[0]?.result || "";

            if (content && content.length > 10) {
                const response = await browser.runtime.sendNativeMessage(
                    "application.id",
                    { action: "summarize", text: content }
                );
                if (response.success) {
                    summary = response.summary;
                }
            }
        } catch (err) {
            // Tab might be a Safari internal page — skip summary
        }

        tabsWithSummaries.push({
            url: tab.url,
            title: tab.title,
            summary: summary
        });
    }

    // Save the tabs with summaries
    try {
        const response = await browser.runtime.sendNativeMessage(
            "application.id",
            { action: "saveTabs", tabs: tabsWithSummaries }
        );

        browser.runtime.sendMessage({
            action: "summarizeComplete",
            success: response.success,
            filePath: response.filePath,
            error: response.error,
            tabs: tabs
        }).catch(() => {});
    } catch (err) {
        browser.runtime.sendMessage({
            action: "summarizeComplete",
            success: false,
            error: err.message,
            tabs: tabs
        }).catch(() => {});
    }
}
