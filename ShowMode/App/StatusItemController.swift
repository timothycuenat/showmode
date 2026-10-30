import AppKit
import Combine
import SwiftUI

/// Icône de la barre des menus : `MenuBarExtra` ne permet pas de réagir au clic, d'où `NSStatusItem`.
@MainActor
final class StatusItemController: NSObject {
    private let controller: ShowModeController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var layoutWindow: NSWindow?
    private var iconObserver: AnyCancellable?

    init(controller: ShowModeController) {
        self.controller = controller
        super.init()

        let content = NSHostingController(rootView: MenuContentView(
            controller: controller,
            openLayoutEditor: { [weak self] in self?.showLayoutEditor() }
        ))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("ShowMode")
        }
        iconObserver = controller.$isActive.sink { [weak self] active in
            self?.statusItem.button?.image = NSImage(named: active ? "MenuBarIconActive" : "MenuBarIcon")
        }
    }

    @objc private func iconClicked() {
        let event = NSApp.currentEvent
        let opensMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if controller.options.toggleOnIconClick && !opensMenu {
            popover.performClose(nil)
            controller.setActive(!controller.isActive)
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showLayoutEditor() {
        popover.performClose(nil)
        let window = layoutWindow ?? makeLayoutWindow()
        layoutWindow = window
        // Une app de barre des menus n'est jamais au premier plan : il faut l'y amener.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeLayoutWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: LayoutEditorView(controller: controller)))
        window.title = String(localized: "Disposition des écrans")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
