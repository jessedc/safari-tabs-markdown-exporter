//
//  ViewController.swift
//  Shared (App)
//
//  Created by Jesse Collis on 13/3/2026.
//

import WebKit
import os.log

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown", category: "app")

let extensionBundleIdentifier = "com.jcmultimedia.TabDown.Extension"
let appGroupID = "group.com.jcmultimedia.TabDown"

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("viewDidLoad: initializing")

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = false
#endif

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("webView didFinish: navigation complete")
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
#elseif os(macOS)
        webView.evaluateJavaScript("show('mac')")

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                logger.error("webView didFinish: failed to get extension state — \(error?.localizedDescription ?? "unknown error", privacy: .public)")
                return
            }

            logger.info("webView didFinish: extension enabled=\(state.isEnabled)")
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
        logger.info("webView didFinish: outputFolder=\(folderPath, privacy: .public), excludedPatterns=\(patterns.count)")
        let patternsJSON = (try? String(data: JSONSerialization.data(withJSONObject: patterns), encoding: .utf8)) ?? "[]"
        webView.evaluateJavaScript("updateSettings('\(folderPath.replacingOccurrences(of: "'", with: "\\'"))', \(patternsJSON))")
#endif
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
#if os(macOS)
        guard let body = message.body as? String else {
            logger.warning("userContentController: received non-string message body")
            return
        }

        logger.info("userContentController: received message=\(body.prefix(50), privacy: .public)")

        switch body {
        case "open-preferences":
            logger.info("userContentController: opening Safari extension preferences")
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                guard error == nil else {
                    logger.error("userContentController: failed to open preferences — \(error!.localizedDescription, privacy: .public)")
                    return
                }
                DispatchQueue.main.async {
                    NSApp.terminate(self)
                }
            }

        case "chooseFolder":
            logger.info("userContentController: presenting folder picker")
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"

            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    logger.info("userContentController: folder picker cancelled")
                    return
                }
                logger.info("userContentController: user selected folder \(url.path, privacy: .public)")
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
                        logger.error("userContentController: failed to get app group container")
                        return
                    }
                    let bookmarkFile = containerURL.appendingPathComponent("outputFolderBookmark")
                    try bookmarkData.write(to: bookmarkFile)
                    logger.info("userContentController: saved folder bookmark (\(bookmarkData.count) bytes)")

                    DispatchQueue.main.async {
                        self?.webView.evaluateJavaScript("setFolderPath('\(url.path.replacingOccurrences(of: "'", with: "\\'"))')")
                    }
                } catch {
                    logger.error("userContentController: failed to save bookmark — \(error.localizedDescription, privacy: .public)")
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
                    logger.info("userContentController: saving \(patterns.count) excluded patterns")
                    saveExcludedPatterns(patterns)
                } else {
                    logger.error("userContentController: failed to parse patterns JSON")
                }
            } else {
                logger.warning("userContentController: unhandled message=\(body, privacy: .public)")
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
