//
//  ViewController.swift
//  Shared (App)
//
//  Created by Jesse Collis on 13/3/2026.
//

import WebKit

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "com.jcmultimedia.TabDown.Extension"
let appGroupID = "group.com.jcmultimedia.TabDown"

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = false
#endif

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
#elseif os(macOS)
        webView.evaluateJavaScript("show('mac')")

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), false)")
                }
            }
        }

        // Send current settings to the web view
        let folderPath = currentOutputFolderPath() ?? ""
        let patterns = loadExcludedPatterns()
        let patternsJSON = (try? String(data: JSONSerialization.data(withJSONObject: patterns), encoding: .utf8)) ?? "[]"
        webView.evaluateJavaScript("updateSettings('\(folderPath.replacingOccurrences(of: "'", with: "\\'"))', \(patternsJSON))")
#endif
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
#if os(macOS)
        guard let body = message.body as? String else { return }

        switch body {
        case "open-preferences":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    NSApp.terminate(self)
                }
            }

        case "chooseFolder":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"

            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
                    let bookmarkFile = containerURL.appendingPathComponent("outputFolderBookmark")
                    try bookmarkData.write(to: bookmarkFile)

                    DispatchQueue.main.async {
                        self?.webView.evaluateJavaScript("setFolderPath('\(url.path.replacingOccurrences(of: "'", with: "\\'"))')")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.webView.evaluateJavaScript("setFolderPath('')")
                    }
                }
            }

        default:
            // Handle pattern updates
            if body.hasPrefix("savePatterns:") {
                let jsonString = String(body.dropFirst("savePatterns:".count))
                if let data = jsonString.data(using: .utf8),
                   let patterns = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    saveExcludedPatterns(patterns)
                }
            }
        }
#endif
    }

#if os(macOS)
    private func currentOutputFolderPath() -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let bookmarkFile = containerURL.appendingPathComponent("outputFolderBookmark")
        guard let bookmarkData = try? Data(contentsOf: bookmarkFile) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return url.path
    }

    private func loadExcludedPatterns() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return [] }
        return defaults.stringArray(forKey: "excludedPatterns") ?? []
    }

    private func saveExcludedPatterns(_ patterns: [String]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(patterns, forKey: "excludedPatterns")
    }
#endif
}
