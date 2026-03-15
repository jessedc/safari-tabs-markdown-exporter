# Safari Extension File Export: Standard Pattern

Safari extensions are heavily sandboxed — the JavaScript side has zero filesystem APIs, and even the native Swift handler runs in a restricted sandbox. There is one standard architecture for writing files, and it requires cooperation between four components.

## The 4-Part Architecture

### 1. Companion App: User Picks a Folder

Every Safari Web Extension ships inside a companion macOS app. The app presents an `NSOpenPanel` so the user can choose an output folder. This is the only way to obtain user consent for a filesystem location — the extension process itself cannot show `NSOpenPanel`.

```swift
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.begin { response in
    guard response == .OK, let url = panel.url else { return }
    // Create a security-scoped bookmark (step 2)
}
```

### 2. Security-Scoped Bookmarks: Persist the Access

After the user picks a folder, the app creates a **security-scoped bookmark** — an opaque `Data` blob that encodes the sandbox grant. Without this, the access is lost when the app quits.

```swift
let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
// Store bookmarkData in the App Group container (step 3)
```

**Required entitlement:** `com.apple.security.files.bookmarks.app-scope`

Bookmarks become "stale" when folders are moved or renamed — always check `isStale` on resolution and regenerate if needed. Bookmarks are device-specific and cannot be synced across machines.

### 3. App Groups: Share the Bookmark with the Extension

The app and extension are separate processes with separate sandboxes. They share data via an **App Group** container.

- Add the "App Groups" capability to both targets in Xcode with the same identifier (e.g., `group.com.example.MyApp`).
- Store the bookmark data using either:
  - **Shared `UserDefaults`:** `UserDefaults(suiteName: "group.com.example.MyApp")`
  - **Shared container directory:** `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.MyApp")`

App Groups are a communication channel, not a sandbox escape. The actual filesystem access still comes from the security-scoped bookmark.

### 4. Native Messaging: Extension Resolves the Bookmark and Writes

When the extension needs to write a file:

**JavaScript side** — sends data to the native handler:

```javascript
const response = await browser.runtime.sendNativeMessage(
    "com.example.MyApp.Extension",
    { action: "saveFile", data: fileContent }
);
```

**Swift side** — in `SafariWebExtensionHandler`, resolves the bookmark, writes the file:

```swift
// Read bookmark data from App Group container
var isStale = false
let url = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)

// Temporarily extend the sandbox to access the folder
guard url.startAccessingSecurityScopedResource() else { return }
defer { url.stopAccessingSecurityScopedResource() }

// Write the file
let fileURL = url.appendingPathComponent("output.md")
try content.write(to: fileURL, atomically: true, encoding: .utf8)
```

## Alternatives (and Why They Don't Work Well)

| Approach | Status |
|---|---|
| `browser.downloads.download()` | **Not supported in Safari.** Available in Chrome/Firefox but Apple has never implemented it. |
| `<a download="...">` attribute | Unreliable in extension contexts; Safari often navigates instead of downloading. |
| Blob URL / data URL | Can trigger Safari's download sheet but gives no control over filename or destination. |
| Clipboard | Copy data for the user to paste — poor UX. |

## Summary

The **native messaging + security-scoped bookmarks + App Groups** pattern is the only robust way for a Safari extension to write files to user-chosen filesystem locations. It requires:

1. A companion app with `NSOpenPanel` for folder selection
2. Security-scoped bookmarks to persist the sandbox grant
3. An App Group to share the bookmark between app and extension
4. Native messaging (`browser.runtime.sendNativeMessage`) to trigger writes from JavaScript

## References

- [Messaging a Web Extension's Native App — Apple Developer](https://developer.apple.com/documentation/SafariServices/messaging-a-web-extension-s-native-app)
- [Accessing Files from the macOS App Sandbox — Apple Developer](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Enabling Security-Scoped Bookmark and URL Access — Apple Developer](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [Meet Safari Web Extensions — WWDC20](https://developer.apple.com/videos/play/wwdc2020/10665/)
