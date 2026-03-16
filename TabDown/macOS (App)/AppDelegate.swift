//
//  AppDelegate.swift
//  macOS (App)
//
//  Created by Jesse Collis on 13/3/2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var isCLIMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--sync") {
            isCLIMode = true
            NSApp.setActivationPolicy(.accessory)

            // Close any storyboard windows before they render
            for window in NSApp.windows {
                window.close()
            }

            runSync()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !isCLIMode
    }

    private func runSync() {
        do {
            let result = try ExportSyncer.sync()
            if result.movedFiles.isEmpty && result.errors.isEmpty {
                print("No files to sync.")
            } else {
                for file in result.movedFiles {
                    print("Moved: \(file)")
                }
                for err in result.errors {
                    FileHandle.standardError.write(Data("Error moving \(err.file): \(err.error)\n".utf8))
                }
            }
            let exitCode: Int32 = result.errors.isEmpty ? 0 : 1
            exit(exitCode)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }

}
