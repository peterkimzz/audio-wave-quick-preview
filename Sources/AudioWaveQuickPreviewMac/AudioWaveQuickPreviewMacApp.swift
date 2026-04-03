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
                }
        }
    }
}
