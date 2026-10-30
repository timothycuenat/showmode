import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ShowModeController()
    private var statusItem: StatusItemController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        controller.start()
        statusItem = StatusItemController(controller: controller)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    /// `kill`, déconnexion, etc. : on passe par la fermeture normale pour tout restaurer.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}
