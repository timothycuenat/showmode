import AppKit

/// Fenêtres noires sans bordure, plein écran sur chaque écran demandé.
final class BlackoutWindowController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func show(on displayIDs: Set<CGDirectDisplayID>) {
        for (id, window) in windows where !displayIDs.contains(id) {
            window.orderOut(nil)
        }
        for id in displayIDs {
            guard let screen = NSScreen.screen(for: id) else {
                windows[id]?.orderOut(nil)
                continue
            }
            let window = windows[id] ?? makeWindow()
            windows[id] = window
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
        }
    }

    func hide() {
        show(on: [])
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}
