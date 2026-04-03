import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFile: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let firstURL = urls.first else { return }
        onOpenFile?(firstURL)
    }
}
