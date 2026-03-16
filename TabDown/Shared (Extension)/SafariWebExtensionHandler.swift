//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 13/3/2026.
//

import SafariServices
import os.log

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown.Extension", category: "handler")

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let message: [String: Any]?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        } else {
            message = request?.userInfo?["message"] as? [String: Any]
        }

        guard let message = message, let action = message["action"] as? String else {
            logger.error("beginRequest: invalid message — no action found")
            sendResponse(context: context, response: ["success": false, "error": "Invalid message"])
            return
        }

        logger.info("beginRequest: action=\(action, privacy: .public)")

        switch action {
        case "saveTabs":
            handleSaveTabs(context: context, message: message)
        case "getSettings":
            handleGetSettings(context: context)
        case "getExcludedPatterns":
            handleGetExcludedPatterns(context: context)
        case "setExcludedPatterns":
            handleSetExcludedPatterns(context: context, message: message)
        case "summarize":
            handleSummarize(context: context, message: message)
        default:
            logger.warning("beginRequest: unknown action=\(action, privacy: .public)")
            sendResponse(context: context, response: ["success": false, "error": "Unknown action: \(action)"])
        }
    }

    private func handleSaveTabs(context: NSExtensionContext, message: [String: Any]) {
        guard let tabs = message["tabs"] as? [[String: Any]] else {
            logger.error("saveTabs: missing tabs array in message")
            sendResponse(context: context, response: ["success": false, "error": "Missing tabs array"])
            return
        }

        logger.info("saveTabs: saving \(tabs.count) tabs")
        let summaryCount = tabs.filter { ($0["summary"] as? String)?.isEmpty == false }.count
        logger.info("saveTabs: \(summaryCount)/\(tabs.count) tabs have summaries")

        do {
            let outputFolder = try BookmarkAccess.exportDirectory()
            logger.info("saveTabs: writing to exports directory=\(outputFolder.path, privacy: .public)")

            let filePath = try TabExporter.saveMarkdown(tabs: tabs, outputFolder: outputFolder)
            logger.info("saveTabs: saved to \(filePath, privacy: .public)")
            sendResponse(context: context, response: ["success": true, "filePath": filePath])
        } catch {
            logger.error("saveTabs: failed — \(error.localizedDescription, privacy: .public)")
            sendResponse(context: context, response: ["success": false, "error": error.localizedDescription])
        }
    }

    private func handleGetSettings(context: NSExtensionContext) {
        let hasFolder = BookmarkAccess.hasOutputFolder()
        logger.info("getSettings: hasOutputFolder=\(hasFolder)")
        sendResponse(context: context, response: [
            "success": true,
            "hasOutputFolder": hasFolder
        ])
    }

    private func handleGetExcludedPatterns(context: NSExtensionContext) {
        let patterns = TabExporter.loadExcludedPatterns()
        logger.info("getExcludedPatterns: \(patterns.count) patterns loaded")
        sendResponse(context: context, response: ["success": true, "patterns": patterns])
    }

    private func handleSetExcludedPatterns(context: NSExtensionContext, message: [String: Any]) {
        guard let patterns = message["patterns"] as? [String] else {
            logger.error("setExcludedPatterns: missing patterns array")
            sendResponse(context: context, response: ["success": false, "error": "Missing patterns array"])
            return
        }
        logger.info("setExcludedPatterns: saving \(patterns.count) patterns")
        TabExporter.saveExcludedPatterns(patterns)
        sendResponse(context: context, response: ["success": true])
    }

    private func handleSummarize(context: NSExtensionContext, message: [String: Any]) {
        guard let text = message["text"] as? String else {
            logger.error("summarize: missing text in message")
            sendResponse(context: context, response: ["success": false, "error": "Missing text"])
            return
        }

        let title = message["title"] as? String
        let url = message["url"] as? String
        logger.info("summarize: received text of \(text.count) chars, title=\(title ?? "nil", privacy: .public)")

        if #available(macOS 26, *) {
            #if canImport(FoundationModels)
            Task {
                let result = await Summarizer.summarize(text: text, title: title, url: url)
                logger.info("summarize: success=\(result.success), summary length=\(result.summary.count)")
                sendResponse(context: context, response: [
                    "success": result.success,
                    "summary": result.summary
                ])
            }
            #else
            logger.warning("summarize: FoundationModels not available at compile time")
            sendResponse(context: context, response: ["success": false, "error": "FoundationModels not available"])
            #endif
        } else {
            logger.warning("summarize: macOS version too old (requires 26+)")
            sendResponse(context: context, response: ["success": false, "error": "Requires macOS 26 or later"])
        }
    }

    private func sendResponse(context: NSExtensionContext, response: [String: Any]) {
        let item = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            item.userInfo = [SFExtensionMessageKey: response]
        } else {
            item.userInfo = ["message": response]
        }
        logger.debug("sendResponse: \(response.keys.sorted().joined(separator: ", "), privacy: .public)")
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
