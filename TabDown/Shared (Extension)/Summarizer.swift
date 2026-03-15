//
//  Summarizer.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown.Extension", category: "summarizer")

@available(macOS 26, *)
struct Summarizer {

    private static let systemPrompt = """
        Summarize the following content in 1-2 concise sentences. \
        Write only the summary — do not start with 'This page', 'The page', \
        'A webpage', 'This web page', or similar references to it being a page. \
        Do not repeat the title. Do not apologize or refuse. \
        If the content is insufficient (e.g. just a title, a login page, \
        or a generic page name), explain briefly why a summary isn't possible, \
        e.g. 'Title only — no content available' or 'Login page — no \
        summarizable content'.
        """

    private static let refusalPrefixes = [
        "i apologize",
        "i'm sorry",
        "sorry",
        "i cannot",
        "i can't",
        "i'm unable",
        "sure, i'd be happy to help",
    ]

    private static let maxWords = 2500

    private static func isRefusal(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return refusalPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func truncateToWords(_ text: String) -> String {
        let words = text.split(separator: " ", maxSplits: maxWords + 1, omittingEmptySubsequences: true)
        if words.count <= maxWords { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }

    #if canImport(FoundationModels)
    static func summarize(text: String) async -> (success: Bool, summary: String) {
        logger.info("summarize: input text \(text.count) chars")
        let truncated = truncateToWords(text)
        if truncated.count < text.count {
            logger.info("summarize: truncated from \(text.count) to \(truncated.count) chars (\(maxWords) word limit)")
        }

        logger.info("summarize: creating LanguageModelSession and sending request")
        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: truncated)
            let result = String(describing: response).trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("summarize: got response, \(result.count) chars")

            if isRefusal(result) {
                logger.warning("summarize: detected refusal in response: \(result.prefix(60), privacy: .public)")
                return (true, "Could not summarize — insufficient content")
            }

            var cleaned = result
            if cleaned.lowercased().hasPrefix("summary:") {
                cleaned = String(cleaned.dropFirst("summary:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                logger.debug("summarize: stripped 'summary:' prefix")
            }
            logger.info("summarize: success, summary=\(cleaned.prefix(80), privacy: .public)...")
            return (true, cleaned)
        } catch {
            let desc = String(describing: error)
            logger.error("summarize: error — \(desc, privacy: .public)")
            if desc.contains("exceededContextWindowSize") || desc.contains("ContextWindowSize") {
                logger.warning("summarize: context window exceeded")
                return (true, "Could not summarize — content too long for on-device model")
            }
            if desc.contains("guardrailViolation") || desc.contains("GuardrailViolation") {
                logger.warning("summarize: guardrail violation")
                return (true, "Could not summarize — content blocked by safety filter")
            }
            return (false, "Summarization error: \(error.localizedDescription)")
        }
    }
    #endif
}
