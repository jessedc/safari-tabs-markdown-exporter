//
//  ExportSyncer.swift
//  Shared (App)
//
//  Created by Jesse Collis on 16/3/2026.
//

#if os(macOS)
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jcmultimedia.TabDown", category: "sync")

struct SyncResult {
    let movedFiles: [String]
    let errors: [(file: String, error: String)]
}

enum SyncError: Error, CustomStringConvertible {
    case noAppGroupContainer
    case noExportsDirectory
    case noOutputFolderConfigured
    case bookmarkResolutionFailed
    case securityScopeAccessDenied(path: String)
    case listDirectoryFailed(String)

    var description: String {
        switch self {
        case .noAppGroupContainer:
            return "Cannot access app group container"
        case .noExportsDirectory:
            return "No exports directory found"
        case .noOutputFolderConfigured:
            return "No output folder configured. Open TabDown.app and select an output folder first."
        case .bookmarkResolutionFailed:
            return "Failed to resolve output folder bookmark"
        case .securityScopeAccessDenied(let path):
            return "Cannot access output folder: \(path)"
        case .listDirectoryFailed(let detail):
            return "Failed to list exports directory: \(detail)"
        }
    }
}

struct ExportSyncer {
    private static let appGroupID = "group.com.jcmultimedia.TabDown"

    /// Moves files from the app group exports directory to the user-selected output folder.
    /// Returns the list of moved files, or throws if the sync cannot proceed.
    static func sync() throws -> SyncResult {
        let fm = FileManager.default
        guard let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.error("sync: cannot get app group container")
            throw SyncError.noAppGroupContainer
        }

        let exportsDir = containerURL.appendingPathComponent("exports")
        guard fm.fileExists(atPath: exportsDir.path) else {
            logger.debug("sync: no exports directory, nothing to sync")
            return SyncResult(movedFiles: [], errors: [])
        }

        // Resolve the user-selected folder via security-scoped bookmark
        let bookmarkFile = containerURL.appendingPathComponent("outputFolderBookmark")
        guard let bookmarkData = try? Data(contentsOf: bookmarkFile) else {
            logger.info("sync: no bookmark file — user has not selected an output folder")
            throw SyncError.noOutputFolderConfigured
        }
        var isStale = false
        guard let outputFolder = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            logger.error("sync: failed to resolve output folder bookmark")
            throw SyncError.bookmarkResolutionFailed
        }
        if isStale {
            logger.warning("sync: bookmark is stale, refreshing")
            if let newData = try? outputFolder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                try? newData.write(to: bookmarkFile)
            }
        }

        guard outputFolder.startAccessingSecurityScopedResource() else {
            logger.error("sync: startAccessingSecurityScopedResource failed for \(outputFolder.path, privacy: .public)")
            throw SyncError.securityScopeAccessDenied(path: outputFolder.path)
        }
        defer { outputFolder.stopAccessingSecurityScopedResource() }

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: exportsDir, includingPropertiesForKeys: nil)
        } catch {
            logger.error("sync: failed to list exports directory — \(error.localizedDescription, privacy: .public)")
            throw SyncError.listDirectoryFailed(error.localizedDescription)
        }

        if files.isEmpty {
            logger.debug("sync: no files to sync")
            return SyncResult(movedFiles: [], errors: [])
        }

        logger.info("sync: syncing \(files.count) file(s) to \(outputFolder.path, privacy: .public)")
        var movedFiles: [String] = []
        var errors: [(file: String, error: String)] = []

        for file in files {
            let dest = outputFolder.appendingPathComponent(file.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: file, to: dest)
                logger.info("sync: moved \(file.lastPathComponent, privacy: .public)")
                movedFiles.append(file.lastPathComponent)
            } catch {
                logger.error("sync: failed to move \(file.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                errors.append((file: file.lastPathComponent, error: error.localizedDescription))
            }
        }

        return SyncResult(movedFiles: movedFiles, errors: errors)
    }
}
#endif
