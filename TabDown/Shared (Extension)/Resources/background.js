const JOB_KEY = "summarizeJob";
const RESUME_ALARM = "summarize-resume";

// In-memory guard so a single worker instance never runs the loop twice.
// Resets when Safari suspends the worker; the persisted job is the real state.
let jobRunning = false;

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("[background] received message:", request.action, "from:", sender?.url || "popup");
    if (request.action === "startSummarization") {
        startJob(request.tabs);
    }
});

if (browser.alarms) {
    browser.alarms.onAlarm.addListener((alarm) => {
        if (alarm.name === RESUME_ALARM) {
            resumeIfNeeded("alarm");
        }
    });
}

async function startJob(tabs) {
    const stored = await browser.storage.local.get(JOB_KEY);
    if (stored[JOB_KEY]?.status === "running") {
        console.warn("[background] job already in progress, resuming instead of restarting");
        resumeIfNeeded("duplicate start");
        return;
    }

    console.log("[background] starting summarization for", tabs.length, "tabs");
    const job = {
        status: "running",
        startedAt: Date.now(),
        tabs: tabs,
        results: [],
        current: 0,
        total: tabs.length,
        stage: "Summarizing"
    };
    await writeJob(job);

    if (browser.alarms) {
        browser.alarms.create(RESUME_ALARM, { periodInMinutes: 1 });
    }
    runJob(job);
}

async function resumeIfNeeded(reason) {
    if (jobRunning) {
        return;
    }
    const stored = await browser.storage.local.get(JOB_KEY);
    const job = stored[JOB_KEY];
    if (job && job.status === "running") {
        console.log(`[background] resuming job (${reason}) at ${job.results.length}/${job.total}`);
        runJob(job);
    } else if (browser.alarms) {
        browser.alarms.clear(RESUME_ALARM);
    }
}

async function runJob(job) {
    if (jobRunning) {
        return;
    }
    jobRunning = true;

    try {
        for (let i = job.results.length; i < job.tabs.length; i++) {
            const tab = job.tabs[i];
            console.log(`[background] processing tab ${i + 1}/${job.total}: "${tab.title}" (${tab.url})`);
            setBadge(`${job.total - i}`);

            const setStage = (stage) => {
                job.stage = stage;
                return writeJob(job);
            };

            const summary = await summarizeTab(tab, setStage);
            job.results.push({
                url: tab.url,
                title: tab.title,
                summary: summary
            });
            job.current = i + 1;
            await writeJob(job);
        }

        console.log("[background] all tabs processed, sending saveTabs to native app");
        const response = await browser.runtime.sendNativeMessage(
            "application.id",
            { action: "saveTabs", tabs: job.results }
        );
        console.log("[background] saveTabs response:", response);

        job.status = response.success ? "done" : "error";
        job.filePath = response.filePath;
        job.error = response.error;
    } catch (err) {
        console.error("[background] job failed:", err.message);
        job.status = "error";
        job.error = err.message;
    }

    await writeJob(job);
    setBadge("");
    if (browser.alarms) {
        browser.alarms.clear(RESUME_ALARM);
    }
    jobRunning = false;
}

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

async function summarizeTab(tab, setStage) {
    try {
        // Tier 1: Extract directly
        await setStage("Extracting");
        console.log(`[background] injecting extract-content.js into tab ${tab.id}`);
        let content = await extractContent(tab.id);
        console.log(`[background] extracted content from tab ${tab.id}: ${content.length} chars`);

        // Tier 2: Reload + re-extract
        if (content.length <= 10) {
            console.log(`[background] tab ${tab.id} appears purged (${content.length} chars), reloading`);
            await setStage("Reloading tab");
            try {
                await forceReloadTab(tab.id);
                await setStage("Extracting");
                content = await extractContent(tab.id);
                console.log(`[background] post-reload content from tab ${tab.id}: ${content.length} chars`);
            } catch (reloadErr) {
                console.warn(`[background] reload failed for tab ${tab.id}:`, reloadErr.message);
            }
        }

        // Tier 3: Activate + extract
        if (content.length <= 10) {
            console.log(`[background] tab ${tab.id} still empty after reload, activating`);
            await setStage("Activating tab");
            try {
                content = await extractWithActivation(tab.id);
                console.log(`[background] post-activation content from tab ${tab.id}: ${content.length} chars`);
            } catch (activateErr) {
                console.warn(`[background] activation failed for tab ${tab.id}:`, activateErr.message);
            }
        }

        if (!content || content.length <= 10) {
            console.warn(`[background] skipping summary for tab ${tab.id}: content too short (${content.length} chars)`);
            return "";
        }

        await setStage("Summarizing");
        console.log(`[background] requesting summary from native app for tab ${tab.id}`);
        const response = await browser.runtime.sendNativeMessage(
            "application.id",
            { action: "summarize", text: content, title: tab.title, url: tab.url }
        );
        console.log(`[background] summarize response for tab ${tab.id}:`, response.success, response.summary?.substring(0, 80));

        if (response.success) {
            return response.summary;
        }
        console.warn(`[background] summarize failed for tab ${tab.id}:`, response.error);
    } catch (err) {
        console.warn(`[background] error processing tab ${tab.id} ("${tab.title}"):`, err.message);
    }
    return "";
}

function writeJob(job) {
    return browser.storage.local.set({ [JOB_KEY]: job });
}

function setBadge(text) {
    try {
        browser.action.setBadgeText({ text });
    } catch (err) {
        // Badge is best-effort only
    }
}

// Whenever Safari wakes this worker (popup opened, alarm fired, message arrived),
// pick up any job that was suspended mid-run.
resumeIfNeeded("worker start");
