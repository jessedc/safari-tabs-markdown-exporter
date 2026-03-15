let excludedPatterns = [];

function show(platform, enabled, useSettingsInsteadOfPreferences) {
    document.body.classList.add(`platform-${platform}`);

    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('platform-mac state-on')[0].innerText = "TabDown's extension is currently on. You can turn it off in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac state-off')[0].innerText = "TabDown's extension is currently off. You can turn it on in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac state-unknown')[0].innerText = "You can turn on TabDown's extension in the Extensions section of Safari Settings.";
        document.getElementsByClassName('platform-mac open-preferences')[0].innerText = "Quit and Open Safari Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function updateSettings(folderPath, patterns) {
    if (folderPath) {
        setFolderPath(folderPath);
    }
    if (patterns && Array.isArray(patterns)) {
        excludedPatterns = patterns;
        renderPatterns();
    }
}

function setFolderPath(path) {
    const el = document.getElementById('folder-path');
    if (path) {
        el.textContent = path;
        el.classList.add('has-path');
    } else {
        el.textContent = 'No folder selected';
        el.classList.remove('has-path');
    }
}

function renderPatterns() {
    const list = document.getElementById('patterns-list');
    list.innerHTML = '';
    excludedPatterns.forEach((pattern, index) => {
        const row = document.createElement('div');
        row.className = 'pattern-row';

        const span = document.createElement('span');
        span.textContent = pattern;
        row.appendChild(span);

        const removeBtn = document.createElement('button');
        removeBtn.textContent = 'Remove';
        removeBtn.className = 'small-btn remove-btn';
        removeBtn.addEventListener('click', () => {
            excludedPatterns.splice(index, 1);
            renderPatterns();
            savePatterns();
        });
        row.appendChild(removeBtn);

        list.appendChild(row);
    });
}

function savePatterns() {
    webkit.messageHandlers.controller.postMessage("savePatterns:" + JSON.stringify(excludedPatterns));
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);

document.getElementById('choose-folder-btn').addEventListener('click', () => {
    webkit.messageHandlers.controller.postMessage("chooseFolder");
});

document.getElementById('add-pattern-btn').addEventListener('click', () => {
    const input = document.getElementById('pattern-input');
    const value = input.value.trim();
    if (value && !excludedPatterns.includes(value)) {
        excludedPatterns.push(value);
        renderPatterns();
        savePatterns();
        input.value = '';
    }
});

document.getElementById('pattern-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        document.getElementById('add-pattern-btn').click();
    }
});
