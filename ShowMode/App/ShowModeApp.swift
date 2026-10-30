import SwiftUI

@main
struct ShowModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // L'icône et les fenêtres sont gérées par `StatusItemController`.
        Settings { EmptyView() }
    }
}
