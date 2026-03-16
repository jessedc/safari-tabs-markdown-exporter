//
//  BookmarkAccess.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown.Extension", category: "bookmark")

struct BookmarkAccess {

    private static let appGroupID = "group.com.jcmultimedia.TabDown"
    private static let bookmarkFileName = "outputFolderBookmark"

    private static var containerURL: URL? {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        if url == nil {
            logger.error("containerURL: failed to get app group container for \(appGroupID, privacy: .public)")
        }
        return url
    }

    private static var bookmarkFileURL: URL? {
        containerURL?.appendingPathComponent(bookmarkFileName)
    }

    static func saveOutputFolder(url: URL) throws {
        logger.info("saveOutputFolder: saving bookmark for \(url.path, privacy: .public)")
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard let fileURL = bookmarkFileURL else {
            logger.error("saveOutputFolder: cannot get bookmark file URL")
            throw NSError(domain: "TabDown", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access App Group container"])
        }
        try bookmarkData.write(to: fileURL)
        logger.info("saveOutputFolder: bookmark saved (\(bookmarkData.count) bytes)")
    }

    /// Returns the exports directory in the app group container.
    /// The extension writes here; the companion app syncs files to the user-selected folder.
    static func exportDirectory() throws -> URL {
        guard let container = containerURL else {
            throw NSError(domain: "TabDown", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access App Group container"])
        }
        let dir = container.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logger.debug("exportDirectory: \(dir.path, privacy: .public)")
        return dir
    }

    static func hasOutputFolder() -> Bool {
        guard let fileURL = bookmarkFileURL else {
            logger.debug("hasOutputFolder: no bookmark file URL available")
            return false
        }
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        logger.debug("hasOutputFolder: \(exists)")
        return exists
    }

}
