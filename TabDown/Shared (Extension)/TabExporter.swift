//
//  TabExporter.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown.Extension", category: "exporter")

struct TabExporter {

    static func saveMarkdown(tabs: [[String: Any]], outputFolder: URL) throws -> String {
        logger.info("saveMarkdown: starting with \(tabs.count) tabs, outputFolder=\(outputFolder.path, privacy: .public)")

        let excludedPatterns = loadExcludedPatterns()
        var processed = filterExcluded(tabs: tabs, patterns: excludedPatterns)
        let excludedCount = tabs.count - processed.count
        logger.info("saveMarkdown: filtered \(excludedCount) excluded tabs (\(excludedPatterns.count) patterns)")

        let beforeDedup = processed.count
        processed = deduplicate(tabs: processed)
        logger.info("saveMarkdown: deduplicated \(beforeDedup - processed.count) tabs")

        processed = sortTabs(tabs: processed)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let filename = "\(dateString)-saved-tabs.md"

        let markdown = renderMarkdown(tabs: processed, dateString: dateString)
        logger.info("saveMarkdown: rendered markdown, \(markdown.count) chars for \(processed.count) tabs")

        let fileURL = outputFolder.appendingPathComponent(filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        logger.info("saveMarkdown: wrote file \(fileURL.path, privacy: .public)")
        return fileURL.path
    }

    static func filterExcluded(tabs: [[String: Any]], patterns: [String]) -> [[String: Any]] {
        guard !patterns.isEmpty else { return tabs }
        return tabs.filter { tab in
            guard let urlString = tab["url"] as? String,
                  let components = URLComponents(string: urlString),
                  let host = components.host else { return true }
            let hostPath = (host + (components.path)).lowercased()
            let excluded = patterns.contains { pattern in
                hostPath.hasPrefix(pattern.lowercased())
            }
            if excluded {
                logger.debug("filterExcluded: excluding \(urlString, privacy: .public)")
            }
            return !excluded
        }
    }

    static func deduplicate(tabs: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        return tabs.filter { tab in
            guard let urlString = tab["url"] as? String,
                  var components = URLComponents(string: urlString) else { return true }
            components.fragment = nil
            let key = components.string ?? urlString
            if seen.contains(key) {
                logger.debug("deduplicate: removing duplicate \(urlString, privacy: .public)")
                return false
            }
            seen.insert(key)
            return true
        }
    }

    static func sortTabs(tabs: [[String: Any]]) -> [[String: Any]] {
        tabs.sorted { a, b in
            let urlA = a["url"] as? String ?? ""
            let urlB = b["url"] as? String ?? ""
            let compA = URLComponents(string: urlA)
            let compB = URLComponents(string: urlB)
            let keyA = ((compA?.host ?? "") + (compA?.path ?? "")).lowercased()
            let keyB = ((compB?.host ?? "") + (compB?.path ?? "")).lowercased()
            return keyA < keyB
        }
    }

    static func renderMarkdown(tabs: [[String: Any]], dateString: String) -> String {
        var lines = [
            "# Safari Tabs Export",
            "",
            "**Date:** \(dateString)",
            "**Tabs:** \(tabs.count)",
            "",
            "---",
            ""
        ]

        for tab in tabs {
            let title = (tab["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (tab["url"] as? String ?? "")
            let url = tab["url"] as? String ?? ""
            lines.append("- [\(title)](\(url))")
            if let summary = tab["summary"] as? String, !summary.isEmpty {
                lines.append("  > \(summary)")
            }
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    static func loadExcludedPatterns() -> [String] {
        guard let defaults = UserDefaults(suiteName: "group.com.jcmultimedia.TabDown") else {
            logger.warning("loadExcludedPatterns: failed to access app group defaults")
            return []
        }
        let patterns = defaults.stringArray(forKey: "excludedPatterns") ?? []
        logger.debug("loadExcludedPatterns: loaded \(patterns.count) patterns")
        return patterns
    }

    static func saveExcludedPatterns(_ patterns: [String]) {
        guard let defaults = UserDefaults(suiteName: "group.com.jcmultimedia.TabDown") else {
            logger.warning("saveExcludedPatterns: failed to access app group defaults")
            return
        }
        defaults.set(patterns, forKey: "excludedPatterns")
        logger.info("saveExcludedPatterns: saved \(patterns.count) patterns")
    }
}
