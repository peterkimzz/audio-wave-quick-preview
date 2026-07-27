import AppKit
import AudioWaveQuickPreviewCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFiles: (([URL]) -> Void)? {
        didSet {
            guard !pendingOpenURLs.isEmpty, let onOpenFiles else { return }
            let pending = pendingOpenURLs
            pendingOpenURLs = []
            onOpenFiles(pending)
        }
    }
    var onKeyboardAction: ((KeyboardShortcutAction) -> Void)?
    private var keyboardMonitor: Any?
    /// Set when files arrive before the handler is wired up.
    private var pendingOpenURLs: [URL] = []

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

            guard
                let action = KeyboardShortcutResolver.action(
                    forKeyCode: event.keyCode,
                    hasModifiers: hasModifiers
                )
            else {
                return event
            }

            self.onKeyboardAction?(action)
            return nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        // The handler is wired in ContentView.onAppear, which can run after a
        // Finder "Open With" delivers the files. Hold them rather than drop them.
        guard let onOpenFiles else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        onOpenFiles(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
