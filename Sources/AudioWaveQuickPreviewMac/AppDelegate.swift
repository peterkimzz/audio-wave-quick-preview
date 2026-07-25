import AudioWaveQuickPreviewCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFile: ((URL) -> Void)?
    var onKeyboardAction: ((KeyboardShortcutAction) -> Void)?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app becomes a regular, activatable app even when launched as
        // a bare executable (e.g. `swift run`), so windows can take keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Don't hijack keys while the user is typing in a text field
            // (the field editor is an NSText); let space/arrows edit normally.
            if let responder = event.window?.firstResponder, responder is NSText {
                return event
            }

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
