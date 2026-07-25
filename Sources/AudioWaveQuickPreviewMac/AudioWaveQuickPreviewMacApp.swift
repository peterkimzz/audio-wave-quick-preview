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
                    appDelegate.onOpenFile = model.open(url:)
                    appDelegate.onKeyboardAction = handleKeyboardAction(_:)
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
            guard let branch = DevWorktreeLabel.currentBranch() else { return base }
            return "\(base) — \(branch)"
        }()
    #endif

    private func handleKeyboardAction(_ action: KeyboardShortcutAction) {
        switch action {
        case .togglePlayback:
            model.togglePlayback()
        case .seekBackward:
            model.seekBackwardByKeyboardInterval()
        case .seekForward:
            model.seekForwardByKeyboardInterval()
        }
    }
}

#if DEBUG
    private enum DevWorktreeLabel {
        /// Reads the current git branch of the worktree this build was compiled from.
        /// Uses `#filePath` (compile-time source path) to locate the package root, so it
        /// resolves the right worktree regardless of the launch working directory.
        static func currentBranch() -> String? {
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

            let out = String(
                decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return (out.isEmpty || out == "HEAD") ? nil : out
        }
    }
#endif
