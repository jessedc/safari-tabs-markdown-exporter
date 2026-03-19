browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("[background] received message:", request.action, "from:", sender?.url || "popup");
    if (request.action === "startSummarization") {
        console.log("[background] starting summarization for", request.tabs.length, "tabs");
        handleSummarization(request.tabs);
    }
});

async function extractContent(tabId) {
    const results = await browser.scripting.executeScript({
        target: { tabId },
        files: ["Readability.js", "extract-content.js"]
    });
    return results?.[results.length - 1]?.result || "";
}

function waitForNavigation(tabId, timeoutMs = 15000) {
    return new Promise((resolve) => {
        let settled = false;
        const settle = (value) => {
            if (settled) return;
            settled = true;
            browser.webNavigation.onCompleted.removeListener(listener);
            clearTimeout(timer);
            resolve(value);
        };

        const listener = (details) => {
            if (details.tabId === tabId && details.frameId === 0) {
                settle(true);
            }
        };

        browser.webNavigation.onCompleted.addListener(listener);
        const timer = setTimeout(() => settle(false), timeoutMs);
    });
}

async function forceReloadTab(tabId) {
    const navPromise = waitForNavigation(tabId, 15000);
    await browser.tabs.reload(tabId);
    return await navPromise;
}

async function extractWithActivation(tabId) {
    // Save current active tab so we can restore it
    const [activeTab] = await browser.tabs.query({ active: true, currentWindow: true });
    const originalActiveTabId = activeTab?.id;

    try {
        // Activate the target tab to force Safari to load it
        await browser.tabs.update(tabId, { active: true });

        // Wait for navigation event, but use a shorter timeout with fallback
        // (bfcache restoration may not fire onCompleted)
        const navPromise = waitForNavigation(tabId, 5000);
        const navigated = await navPromise;

        if (!navigated) {
            // bfcache case — give it a moment to settle
            await new Promise(r => setTimeout(r, 1000));
        }

        return await extractContent(tabId);
    } finally {
        // Restore original active tab
        if (originalActiveTabId && originalActiveTabId !== tabId) {
            try {
                await browser.tabs.update(originalActiveTabId, { active: true });
            } catch (err) {
                console.warn(`[background] could not restore active tab:`, err.message);
            }
        }
    }
}

async function handleSummarization(tabs) {
    const tabsWithSummaries = [];

    for (let i = 0; i < tabs.length; i++) {
        const tab = tabs[i];
        console.log(`[background] processing tab ${i + 1}/${tabs.length}: "${tab.title}" (${tab.url})`);

        let summary = "";
        try {
            const sendProgress = (status) => {
                browser.runtime.sendMessage({
                    action: "summarizeProgress",
                    current: i + 1,
                    total: tabs.length,
                    status
                }).catch(() => {});
            };

            // Tier 1: Extract directly
            sendProgress("Extracting");
            console.log(`[background] injecting extract-content.js into tab ${tab.id}`);
            let content = await extractContent(tab.id);
            console.log(`[background] extracted content from tab ${tab.id}: ${content.length} chars`);

            // Tier 2: Reload + re-extract
            if (content.length <= 10) {
                console.log(`[background] tab ${tab.id} appears purged (${content.length} chars), reloading`);
                sendProgress("Reloading tab");
                try {
                    await forceReloadTab(tab.id);
                    sendProgress("Extracting");
                    content = await extractContent(tab.id);
                    console.log(`[background] post-reload content from tab ${tab.id}: ${content.length} chars`);
                } catch (reloadErr) {
                    console.warn(`[background] reload failed for tab ${tab.id}:`, reloadErr.message);
                }
            }

            // Tier 3: Activate + extract
            if (content.length <= 10) {
                console.log(`[background] tab ${tab.id} still empty after reload, activating`);
                sendProgress("Activating tab");
                try {
                    content = await extractWithActivation(tab.id);
                    console.log(`[background] post-activation content from tab ${tab.id}: ${content.length} chars`);
                } catch (activateErr) {
                    console.warn(`[background] activation failed for tab ${tab.id}:`, activateErr.message);
                }
            }

            if (content && content.length > 10) {
                sendProgress("Summarizing");
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
