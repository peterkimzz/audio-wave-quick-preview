import AudioWaveQuickPreviewCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFile: ((URL) -> Void)?
    var onKeyboardAction: ((KeyboardShortcutAction) -> Void)?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let hasModifiers = !event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
                .isEmpty

            guard let action = KeyboardShortcutResolver.action(
                forKeyCode: event.keyCode,
                hasModifiers: hasModifiers
            ) else {
                return event
            }

            self.onKeyboardAction?(action)
            return nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let firstURL = urls.first else { return }
        onOpenFile?(firstURL)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
