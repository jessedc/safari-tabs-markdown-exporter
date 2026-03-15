//
//  TabExporter.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import Foundation

struct TabExporter {

    static func saveMarkdown(tabs: [[String: Any]], outputFolder: URL) throws -> String {
        let excludedPatterns = loadExcludedPatterns()
        var processed = filterExcluded(tabs: tabs, patterns: excludedPatterns)
        processed = deduplicate(tabs: processed)
        processed = sortTabs(tabs: processed)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let filename = "\(dateString)-saved-tabs.md"

        let markdown = renderMarkdown(tabs: processed, dateString: dateString)

        let fileURL = outputFolder.appendingPathComponent(filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    static func filterExcluded(tabs: [[String: Any]], patterns: [String]) -> [[String: Any]] {
        guard !patterns.isEmpty else { return tabs }
        return tabs.filter { tab in
            guard let urlString = tab["url"] as? String,
                  let components = URLComponents(string: urlString),
                  let host = components.host else { return true }
            let hostPath = (host + (components.path)).lowercased()
            return !patterns.contains { pattern in
                hostPath.hasPrefix(pattern.lowercased())
            }
        }
    }

    static func deduplicate(tabs: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        return tabs.filter { tab in
            guard let urlString = tab["url"] as? String,
                  var components = URLComponents(string: urlString) else { return true }
            components.fragment = nil
            let key = components.string ?? urlString
            if seen.contains(key) { return false }
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
        guard let defaults = UserDefaults(suiteName: "group.com.jcmultimedia.TabDown") else { return [] }
        return defaults.stringArray(forKey: "excludedPatterns") ?? []
    }

    static func saveExcludedPatterns(_ patterns: [String]) {
        guard let defaults = UserDefaults(suiteName: "group.com.jcmultimedia.TabDown") else { return }
        defaults.set(patterns, forKey: "excludedPatterns")
    }
}
