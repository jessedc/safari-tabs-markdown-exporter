//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 13/3/2026.
//

import SafariServices
import os.log

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
            sendResponse(context: context, response: ["success": false, "error": "Invalid message"])
            return
        }

        os_log(.default, "TabDown: received action: %@", action)

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
            sendResponse(context: context, response: ["success": false, "error": "Unknown action: \(action)"])
        }
    }

    private func handleSaveTabs(context: NSExtensionContext, message: [String: Any]) {
        guard let tabs = message["tabs"] as? [[String: Any]] else {
            sendResponse(context: context, response: ["success": false, "error": "Missing tabs array"])
            return
        }

        do {
            let outputFolder = try BookmarkAccess.resolveOutputFolder()
            guard outputFolder.startAccessingSecurityScopedResource() else {
                sendResponse(context: context, response: ["success": false, "error": "Cannot access output folder"])
                return
            }
            defer { outputFolder.stopAccessingSecurityScopedResource() }

            let filePath = try TabExporter.saveMarkdown(tabs: tabs, outputFolder: outputFolder)
            sendResponse(context: context, response: ["success": true, "filePath": filePath])
        } catch {
            sendResponse(context: context, response: ["success": false, "error": error.localizedDescription])
        }
    }

    private func handleGetSettings(context: NSExtensionContext) {
        sendResponse(context: context, response: [
            "success": true,
            "hasOutputFolder": BookmarkAccess.hasOutputFolder()
        ])
    }

    private func handleGetExcludedPatterns(context: NSExtensionContext) {
        let patterns = TabExporter.loadExcludedPatterns()
        sendResponse(context: context, response: ["success": true, "patterns": patterns])
    }

    private func handleSetExcludedPatterns(context: NSExtensionContext, message: [String: Any]) {
        guard let patterns = message["patterns"] as? [String] else {
            sendResponse(context: context, response: ["success": false, "error": "Missing patterns array"])
            return
        }
        TabExporter.saveExcludedPatterns(patterns)
        sendResponse(context: context, response: ["success": true])
    }

    private func handleSummarize(context: NSExtensionContext, message: [String: Any]) {
        guard let text = message["text"] as? String else {
            sendResponse(context: context, response: ["success": false, "error": "Missing text"])
            return
        }

        if #available(macOS 26, *) {
            #if canImport(FoundationModels)
            Task {
                let result = await Summarizer.summarize(text: text)
                sendResponse(context: context, response: [
                    "success": result.success,
                    "summary": result.summary
                ])
            }
            #else
            sendResponse(context: context, response: ["success": false, "error": "FoundationModels not available"])
            #endif
        } else {
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
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
