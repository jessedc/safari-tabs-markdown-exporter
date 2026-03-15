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
    // Restore checkbox states
    const stored = await browser.storage.local.get(["closeTabs", "includeSummaries"]);
    closeTabsCheckbox.checked = stored.closeTabs || false;
    includeSummariesCheckbox.checked = stored.includeSummaries || false;

    // Check if output folder is configured
    const settings = await browser.runtime.sendNativeMessage(
        "application.id",
        { action: "getSettings" }
    );

    if (settings.hasOutputFolder) {
        mainUI.classList.remove("hidden");
    } else {
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
    saveBtn.disabled = true;
    resultEl.classList.add("hidden");

    try {
        const allTabs = await browser.tabs.query({});
        const tabs = allTabs.map(t => ({ url: t.url, title: t.title, id: t.id }));

        if (tabs.length === 0) {
            showResult("No tabs found.", "error");
            saveBtn.disabled = false;
            return;
        }

        savedTabIds = tabs.map(t => t.id);

        if (includeSummariesCheckbox.checked) {
            // Delegate to background for summarization
            progressEl.classList.remove("hidden");
            progressText.textContent = "Starting summarization...";

            browser.runtime.sendMessage({
                action: "startSummarization",
                tabs: tabs
            });
        } else {
            // Direct save without summaries
            progressEl.classList.remove("hidden");
            progressText.textContent = "Saving...";

            const tabData = tabs.map(t => ({ url: t.url, title: t.title }));
            const response = await browser.runtime.sendNativeMessage(
                "application.id",
                { action: "saveTabs", tabs: tabData }
            );

            progressEl.classList.add("hidden");

            if (response.success) {
                showResult(`Saved to ${response.filePath}`, "success");
                maybeCloseTabs(tabs);
            } else {
                showResult(response.error || "Save failed", "error");
                saveBtn.disabled = false;
            }
        }
    } catch (err) {
        progressEl.classList.add("hidden");
        showResult(err.message, "error");
        saveBtn.disabled = false;
    }
});

// Listen for messages from background script
browser.runtime.onMessage.addListener((message) => {
    if (message.action === "summarizeProgress") {
        progressText.textContent = `Summarizing ${message.current}/${message.total}...`;
    } else if (message.action === "summarizeComplete") {
        progressEl.classList.add("hidden");
        if (message.success) {
            showResult(`Saved to ${message.filePath}`, "success");
            maybeCloseTabs(message.tabs);
        } else {
            showResult(message.error || "Save failed", "error");
            saveBtn.disabled = false;
        }
    }
});

function maybeCloseTabs(tabs) {
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
        await browser.tabs.remove(idsToClose);
        confirmDialog.classList.add("hidden");
        resultEl.classList.remove("hidden");
        resultText.textContent += " — tabs closed.";
    };

    confirmNo.onclick = () => {
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
