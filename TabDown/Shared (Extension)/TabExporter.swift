//
//  TabExporter.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import DomainParser
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

    private static let excludedSchemes: Set<String> = ["favorites", "history", "bookmarks"]
    private static let excludedURLs: Set<String> = ["about:blank"]

    static func filterExcluded(tabs: [[String: Any]], patterns: [String]) -> [[String: Any]] {
        return tabs.filter { tab in
            guard let urlString = tab["url"] as? String else { return true }

            // Exclude built-in Safari URLs
            if excludedURLs.contains(urlString) {
                logger.debug("filterExcluded: excluding built-in URL \(urlString, privacy: .public)")
                return false
            }
            if let scheme = URLComponents(string: urlString)?.scheme?.lowercased(),
               excludedSchemes.contains(scheme) {
                logger.debug("filterExcluded: excluding built-in scheme \(urlString, privacy: .public)")
                return false
            }

            guard let components = URLComponents(string: urlString),
                  let host = components.host else { return true }
            guard !patterns.isEmpty else { return true }
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

    private static let domainParser = try? DomainParser()

    /// Extracts the registrable domain from a host string using the Public Suffix List.
    static func registrableDomain(from host: String) -> String {
        if let domain = domainParser?.parse(host: host)?.domain {
            return domain
        }
        return host.lowercased()
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

        // Group tabs by top-level domain
        var groups: [(tld: String, tabs: [[String: Any]])] = []
        var groupIndex: [String: Int] = [:]

        for tab in tabs {
            let url = tab["url"] as? String ?? ""
            let host = URLComponents(string: url)?.host ?? ""
            let tld = host.isEmpty ? "" : registrableDomain(from: host)

            if let idx = groupIndex[tld] {
                groups[idx].tabs.append(tab)
            } else {
                groupIndex[tld] = groups.count
                groups.append((tld: tld, tabs: [tab]))
            }
        }

        // Sort groups alphabetically by TLD
        groups.sort { $0.tld < $1.tld }

        for group in groups {
            if !group.tld.isEmpty {
                lines.append("### \(group.tld)")
            }
            for tab in group.tabs {
                let title = (tab["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (tab["url"] as? String ?? "")
                let url = tab["url"] as? String ?? ""
                let domain = URLComponents(string: url)?.host ?? ""
                let displayTitle = domain.isEmpty ? title : "\(title) (\(domain))"
                lines.append("- [\(displayTitle)](\(url))")
                if let summary = tab["summary"] as? String, !summary.isEmpty {
                    lines.append("  > \(summary)")
                }
            }
            lines.append("")
        }

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
