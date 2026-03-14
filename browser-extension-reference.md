# Browser Extension Project — Key Reference

_Summary of research conversation covering Safari, Chrome, and Firefox extension development._

---

## Extension Architecture

### Safari
- Built using the **WebExtensions API** (same standard as Chrome/Firefox)
- Must be wrapped in a **containing macOS/iOS app** — standalone extensions are not allowed
- Distributed exclusively via the **App Store** — no sideloading on iOS
- Two Xcode targets: the containing app + the extension
- Created via: `File → New → Project → Safari Extension App`
- Convert existing Chrome extensions: `xcrun safari-web-extension-converter /path/to/extension`

### Cross-Browser Compatibility
- All three browsers share the **WebExtensions API** — core JS/HTML/CSS is largely portable
- Use [`webextension-polyfill`](https://github.com/mozilla/webextension-polyfill) to smooth over namespace differences

| Area | Chrome | Firefox | Safari |
|---|---|---|---|
| Namespace | `chrome.*` | `browser.*` (Promise-based) | `browser.*` |
| Manifest version | MV3 required | MV2 still supported | MV3 |
| Background scripts | Service workers only | Persistent still supported | Service workers (limited on iOS) |
| Distribution | Chrome Web Store | AMO (addons.mozilla.org) | App Store (inside app) |

---

## Extracting Page Content

### Best Methods (in order of preference for article/content use cases)

1. **Mozilla Readability** — strips boilerplate, best signal-to-noise for article text
   ```javascript
   const documentClone = document.cloneNode(true);
   const reader = new Readability(documentClone);
   const article = reader.parse();
   // article.textContent = clean prose only
   ```

2. **`document.body.innerText`** — all visible text, simple, no dependencies

3. **`window.getSelection().toString()`** — user-selected text only

4. **Targeted DOM queries** — for specific elements (`article`, `main`, `p` tags)

### Injecting Content Scripts
```javascript
// On-demand injection (better for performance)
browser.scripting.executeScript({
  target: { tabId: tabId },
  func: () => document.body.innerText
}).then(results => {
  const text = results[0].result;
});
```

---

## Apple Intelligence / Foundation Models

### Key Constraint: 4,096 Token Context Window
- Hard limit — **input + output combined**
- Apple rule of thumb: ~3–4 characters per token → ~12,000–16,000 characters total budget
- Exceeding the limit throws `GenerationError.exceededContextWindowSize` — **no graceful trimming**
- No public tokenizer API; token counting must be estimated heuristically

### Practical Implications for Page Summarization
- A typical article after Readability extraction can easily exceed the token budget
- **Pre-truncate** extracted text before sending (stay under ~2,500 words to be safe)
- Or **chunk and summarize**: split → summarize sections → summarize summaries
- Trigger summarization at **70–80% of budget** to avoid hitting the wall mid-session

### Safari-Only
- Foundation Models / Apple Intelligence is **unavailable in Chrome and Firefox**
- For cross-browser summarization, route through an external API (OpenAI, Claude, etc.) from the background service worker, or have all browsers call through the native messaging host

---

## Native Messaging (Extension ↔ Companion App)

### Shared API (all browsers)
```javascript
// Works in Safari, Chrome, and Firefox
browser.runtime.sendNativeMessage("com.yourapp.host", { request: "doSomething" });
// Or persistent port:
const port = browser.runtime.connectNative("com.yourapp.host");
```

### Safari vs Chrome/Firefox Registration

| | Safari | Chrome & Firefox |
|---|---|---|
| Registration | Automatic via App Store | Manifest JSON written to OS path |
| Protocol | `NSExtensionRequestHandling` | stdio (stdin/stdout) |
| Host process | Containing app | Separate helper binary |

**Chrome manifest path (macOS):**
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.yourapp.json`

**Firefox manifest path (macOS):**
`~/Library/Application Support/Mozilla/NativeMessagingHosts/com.yourapp.json`

---

## Single Companion App for All Three Browsers

### Yes — one macOS app can serve Safari, Chrome, and Firefox simultaneously.

**Recommended app bundle structure:**
```
YourApp.app/
  Contents/
    MacOS/
      YourApp                   ← main app UI
      YourAppHelper             ← stdio host for Chrome/Firefox
    Extensions/
      YourApp Extension.appex   ← Safari extension bundle
    Frameworks/
      YourAppCore.framework     ← shared business logic
```

- Safari uses the app extension target (`NSExtensionRequestHandling`)
- Chrome/Firefox launch `YourAppHelper` as a subprocess via stdio
- Both entry points share `YourAppCore.framework`
- App writes Chrome/Firefox manifest JSON files on first launch

### What's Shared vs. Separate

| Thing | Shared? |
|---|---|
| Business logic / AI features | ✅ Shared framework |
| Extension JS/HTML/CSS | ✅ Same source |
| `manifest.json` | ⚠️ Mostly — minor per-browser tweaks |
| Native messaging handler | ⚠️ Different entry points, shared logic |
| App Store submission | ❌ Safari only |
| Chrome Web Store submission | ❌ Chrome only |
| AMO submission | ❌ Firefox only |
| Extension IDs (`allowed_extensions`) | ❌ Each browser issues its own |

> **Note:** Chrome extension ID is only known after uploading to the Web Store — you'll need a mechanism to embed it in the manifest your app writes to disk.

---

## iCloud / Data Sync

- Safari extensions **cannot access iCloud tabs** (other devices' open tabs) — `browser.tabs` is local-session only
- The **containing app** can read/write iCloud Drive via `FileManager` + ubiquity containers
- Extensions can trigger iCloud operations indirectly via native messaging → companion app
- **App Groups** provide a lightweight shared storage layer between the extension and app without full native messaging:
  ```swift
  let defaults = UserDefaults(suiteName: "group.com.yourapp.shared")
  ```

---

## Companion App Considerations

- Apple **requires** the companion app to provide meaningful functionality — shell apps get rejected
- Common uses: settings/config, onboarding, feature dashboards, saved content library
- Safari popup UI is constrained in size — anything needing real screen real estate belongs in the companion app
- App Groups + Darwin notifications (`CFNotificationCenter`) are a lightweight alternative to native messaging for simple state sharing

---

## Distribution Summary

| Browser | Extension Store | Companion App Distribution |
|---|---|---|
| Safari | App Store (bundled) | App Store (same submission) |
| Chrome | Chrome Web Store ($5 one-time) | Your own installer / DMG |
| Firefox | AMO — free | Your own installer / DMG |

- Firefox has stricter **source code review** requirements than Chrome
- Firefox supports **self-hosted/unlisted** extensions (useful for enterprise or beta)
