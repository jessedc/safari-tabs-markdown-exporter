//
//  BookmarkAccess.swift
//  Shared (Extension)
//
//  Created by Jesse Collis on 14/3/2026.
//

import Foundation

struct BookmarkAccess {

    private static let appGroupID = "group.com.jcmultimedia.TabDown"
    private static let bookmarkFileName = "outputFolderBookmark"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var bookmarkFileURL: URL? {
        containerURL?.appendingPathComponent(bookmarkFileName)
    }

    static func saveOutputFolder(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard let fileURL = bookmarkFileURL else {
            throw NSError(domain: "TabDown", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access App Group container"])
        }
        try bookmarkData.write(to: fileURL)
    }

    static func resolveOutputFolder() throws -> URL {
        guard let fileURL = bookmarkFileURL else {
            throw NSError(domain: "TabDown", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access App Group container"])
        }
        let bookmarkData = try Data(contentsOf: fileURL)
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            let newData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try newData.write(to: fileURL)
        }
        return url
    }

    static func hasOutputFolder() -> Bool {
        guard let fileURL = bookmarkFileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
