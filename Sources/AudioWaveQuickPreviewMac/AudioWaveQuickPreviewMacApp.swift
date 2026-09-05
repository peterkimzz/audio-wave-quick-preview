import AudioWaveQuickPreviewCore
import Foundation
import SwiftUI

@main
struct AudioWaveQuickPreviewMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            let content = ContentView(model: model)
                .onAppear {
                    appDelegate.onOpenFiles = { model.handleExternalOpen(urls: $0) }
                    appDelegate.onKeyboardAction = handleKeyboardAction(_:)
                    #if DEBUG
                        DebugSelfCheck.runIfRequested(model: model)
                    #endif
                }
            #if DEBUG
                content.navigationTitle(Self.devWindowTitle)
            #else
                content
            #endif
        }
    }

    #if DEBUG
        // ponytail: DEBUG-only worktree label so parallel instances are distinguishable; release keeps the clean title.
        private static let devWindowTitle: String = {
            let base = "Audio Wave Quick Preview"
            guard let label = DevWorktreeLabel.currentLabel() else { return base }
            return "\(base) — \(label)"
        }()
    #endif

    private func handleKeyboardAction(_ action: KeyboardShortcutAction) {
        switch action {
        case .togglePlayback:
            model.toggleActiveLanePlayback()
        case .seekBackward:
            model.seekActiveLaneBackward()
        case .seekForward:
            model.seekActiveLaneForward()
        }
    }
}

#if DEBUG
    private enum DevWorktreeLabel {
        /// Resolves the branch or detached-worktree label for the source this build came from.
        /// Uses `#filePath` (compile-time source path) to locate the package root, so it
        /// resolves the right worktree regardless of the launch working directory.
        static func currentLabel() -> String? {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // AudioWaveQuickPreviewMac (target dir)
                .deletingLastPathComponent()  // Sources
                .deletingLastPathComponent()  // package / worktree root

            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            git.currentDirectoryURL = root
            let pipe = Pipe()
            git.standardOutput = pipe
            git.standardError = FileHandle.nullDevice

            guard (try? git.run()) != nil else { return nil }
            git.waitUntilExit()
            guard git.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let out = String(bytes: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }

            if !out.isEmpty, out != "HEAD" {
                return out
            }

            // Codex-managed worktrees are normally detached, so there is no
            // branch name to show. Use the stable Codex worktree id instead.
            let components = root.standardizedFileURL.pathComponents
            if let worktreesIndex = components.lastIndex(of: "worktrees"), worktreesIndex + 1 < components.count {
                return "worktree-\(components[worktreesIndex + 1])"
            }

            // Keep detached worktrees created outside Codex distinguishable too.

            let pathTail =
                components
                .filter { $0 != "/" }
                .suffix(2)
                .joined(separator: "-")
            return pathTail.isEmpty ? nil : "worktree-\(pathTail)"
        }
    }
#endif
