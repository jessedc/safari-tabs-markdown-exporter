const noFolderEl = document.getElementById("no-folder");
const mainUI = document.getElementById("main-ui");
const saveBtn = document.getElementById("save-btn");
const closeTabsCheckbox = document.getElementById("close-tabs");
const includeSummariesCheckbox = document.getElementById("include-summaries");
const progressEl = document.getElementById("progress");
const progressText = progressEl.querySelector(".progress-text");
const resultEl = document.getElementById("result");
const resultText = document.getElementById("result-text");
const confirmDialog = document.getElementById("confirm-dialog");
const confirmText = document.getElementById("confirm-text");
const confirmYes = document.getElementById("confirm-yes");
const confirmNo = document.getElementById("confirm-no");

let savedTabIds = [];

async function init() {
    console.log("[popup] init: starting");

    // Restore checkbox states
    const stored = await browser.storage.local.get(["closeTabs", "includeSummaries"]);
    console.log("[popup] init: restored settings", stored);
    closeTabsCheckbox.checked = stored.closeTabs || false;
    includeSummariesCheckbox.checked = stored.includeSummaries || false;

    // Check if output folder is configured
    try {
        const settings = await browser.runtime.sendNativeMessage(
            "application.id",
            { action: "getSettings" }
        );
        console.log("[popup] init: getSettings response", settings);

        if (settings.hasOutputFolder) {
            mainUI.classList.remove("hidden");
        } else {
            console.warn("[popup] init: no output folder configured");
            noFolderEl.classList.remove("hidden");
        }
    } catch (err) {
        console.error("[popup] init: getSettings failed", err);
        noFolderEl.classList.remove("hidden");
    }
}

closeTabsCheckbox.addEventListener("change", () => {
    browser.storage.local.set({ closeTabs: closeTabsCheckbox.checked });
});

includeSummariesCheckbox.addEventListener("change", () => {
    browser.storage.local.set({ includeSummaries: includeSummariesCheckbox.checked });
});

saveBtn.addEventListener("click", async () => {
    console.log("[popup] save: button clicked");
    saveBtn.disabled = true;
    resultEl.classList.add("hidden");

    try {
        const allTabs = await browser.tabs.query({});
        const tabs = allTabs
            .filter(t => t.url && t.url !== "about:blank")
            .map(t => ({ url: t.url, title: t.title || t.url, id: t.id, status: t.status }));
        console.log("[popup] save: queried tabs, count =", tabs.length);

        if (tabs.length === 0) {
            console.warn("[popup] save: no tabs found");
            showResult("No tabs found.", "error");
            saveBtn.disabled = false;
            return;
        }

        savedTabIds = tabs.map(t => t.id);

        if (includeSummariesCheckbox.checked) {
            // Delegate to background for summarization
            console.log("[popup] save: delegating to background for summarization");
            progressEl.classList.remove("hidden");
            progressText.textContent = "Starting summarization...";

            browser.runtime.sendMessage({
                action: "startSummarization",
                tabs: tabs
            });
        } else {
            // Direct save without summaries
            console.log("[popup] save: saving without summaries");
            progressEl.classList.remove("hidden");
            progressText.textContent = "Saving...";

            const tabData = tabs.map(t => ({ url: t.url, title: t.title }));
            console.log("[popup] save: sending saveTabs to native, tab count =", tabData.length);
            const response = await browser.runtime.sendNativeMessage(
                "application.id",
                { action: "saveTabs", tabs: tabData }
            );
            console.log("[popup] save: saveTabs response", response);

            progressEl.classList.add("hidden");

            if (response.success) {
                showResult(`Saved to ${response.filePath}`, "success");
                maybeCloseTabs(tabs);
            } else {
                console.error("[popup] save: saveTabs failed", response.error);
                showResult(response.error || "Save failed", "error");
                saveBtn.disabled = false;
            }
        }
    } catch (err) {
        console.error("[popup] save: exception", err);
        progressEl.classList.add("hidden");
        showResult(err.message, "error");
        saveBtn.disabled = false;
    }
});

// Listen for messages from background script
browser.runtime.onMessage.addListener((message) => {
    console.log("[popup] received message:", message.action, message);
    if (message.action === "summarizeProgress") {
        const status = message.status ? `${message.status}` : "Summarizing";
        progressText.textContent = `${status} ${message.current}/${message.total}...`;
    } else if (message.action === "summarizeComplete") {
        console.log("[popup] summarization complete, success =", message.success);
        progressEl.classList.add("hidden");
        if (message.success) {
            showResult(`Saved to ${message.filePath}`, "success");
            maybeCloseTabs(message.tabs);
        } else {
            console.error("[popup] summarization failed:", message.error);
            showResult(message.error || "Save failed", "error");
            saveBtn.disabled = false;
        }
    }
});

function maybeCloseTabs(tabs) {
    console.log("[popup] maybeCloseTabs: closeTabs =", closeTabsCheckbox.checked, "tab count =", tabs.length);
    if (!closeTabsCheckbox.checked || tabs.length <= 1) {
        saveBtn.disabled = false;
        return;
    }

    mainUI.classList.add("hidden");
    confirmDialog.classList.remove("hidden");
    confirmText.textContent = `Close ${tabs.length} tabs?`;

    confirmYes.onclick = async () => {
        const activeTab = await browser.tabs.query({ active: true, currentWindow: true });
        const activeId = activeTab[0]?.id;
        const idsToClose = savedTabIds.filter(id => id !== activeId);
        console.log("[popup] closing tabs: count =", idsToClose.length, "keeping active =", activeId);
        await browser.tabs.remove(idsToClose);
        confirmDialog.classList.add("hidden");
        resultEl.classList.remove("hidden");
        resultText.textContent += " — tabs closed.";
    };

    confirmNo.onclick = () => {
        console.log("[popup] user declined tab close");
        confirmDialog.classList.add("hidden");
        mainUI.classList.remove("hidden");
        saveBtn.disabled = false;
    };
}

function showResult(text, type) {
    resultEl.classList.remove("hidden");
    resultText.textContent = text;
    resultText.className = type || "";
}

init();
