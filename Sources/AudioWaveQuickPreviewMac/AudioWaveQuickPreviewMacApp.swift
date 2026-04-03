import AudioWaveQuickPreviewCore
import SwiftUI

@main
struct AudioWaveQuickPreviewMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    appDelegate.onOpenFile = model.open(url:)
                    appDelegate.onKeyboardAction = handleKeyboardAction(_:)
                }
        }
    }

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
