import AppKit
import CoreGraphics

final class CursorController {
    /// Écrans interdits au curseur : il est ramené dès qu'il y entre.
    var forbiddenDisplayIDs: Set<CGDirectDisplayID> = [] {
        didSet {
            guard forbiddenDisplayIDs != oldValue else { return }
            if forbiddenDisplayIDs.isEmpty {
                stopConfining()
            } else if oldValue.isEmpty {
                startConfining()
            } else {
                clampCursor()
            }
        }
    }

    /// Délai d'inactivité avant masquage ; `nil` désactive et réaffiche le curseur.
    var idleHideDelay: TimeInterval? {
        didSet {
            guard idleHideDelay != oldValue else { return }
            idleHideDelay == nil ? stopIdleTimer() : startIdleTimer()
        }
    }

    private var monitors: [Any] = []
    private var idleTimer: Timer?
    private var isCursorHidden = false
    private var lastAllowedLocation: CGPoint?

    // MARK: - Confinement

    private func startConfining() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.clampCursor()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.clampCursor()
            return event
        }) {
            monitors.append(local)
        }
        clampCursor()
    }

    private func stopConfining() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        lastAllowedLocation = nil
    }

    private func clampCursor() {
        guard let location = CGEvent(source: nil)?.location else { return }
        guard forbiddenDisplayIDs.contains(where: { CGDisplayBounds($0).contains(location) }) else {
            lastAllowedLocation = location
            return
        }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        CGWarpMouseCursorPosition(lastAllowedLocation ?? CGPoint(x: bounds.midX, y: bounds.midY))
        // Annule le court gel du curseur que provoque le déplacement forcé.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Masquage après inactivité

    private func startIdleTimer() {
        BackgroundCursorPermission.enable()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateCursorVisibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        setCursorHidden(false)
    }

    private func updateCursorVisibility() {
        guard let delay = idleHideDelay else { return }
        setCursorHidden(secondsSinceLastMouseActivity() >= delay)
    }

    /// Seule la souris compte : un GO au clavier ne doit pas faire réapparaître le curseur.
    private func secondsSinceLastMouseActivity() -> TimeInterval {
        let events: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown,
            .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .scrollWheel,
        ]
        return events
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != isCursorHidden else { return }
        isCursorHidden = hidden
        if hidden {
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }
}

/// macOS n'autorise le masquage du curseur qu'à l'application au premier plan, ce qu'une app
/// de barre des menus n'est pas. Aucune API publique ne lève cette limite : on utilise cette
/// propriété privée, résolue dynamiquement pour qu'une disparition n'empêche pas le lancement.
private enum BackgroundCursorPermission {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let propertySymbol = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
