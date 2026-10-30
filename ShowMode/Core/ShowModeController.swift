import AppKit
import Combine

/// Orchestre les modules système : chaque fonction est appliquée ou restaurée
/// selon l'état voulu, et peut donc être basculée en direct pendant un spectacle.
@MainActor
final class ShowModeController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var displays: [ExternalDisplay] = []
    @Published private(set) var options = ShowOptions.load()
    @Published private(set) var lastError: String?
    @Published private(set) var hasLayoutToRestore = false
    @Published private(set) var arrangement: [ArrangedDisplay] = []

    private let store = SnapshotStore()
    private var snapshot = SystemSnapshot() {
        didSet { hasLayoutToRestore = snapshot.displayOrigins != nil }
    }
    private let displayManager = DisplayManager()
    private let systemDefaults = SystemDefaultsController()
    private let wallpaper = WallpaperController()
    private let gestures = GestureController()
    private let blackout = BlackoutWindowController()
    private let cursor = CursorController()
    private let notifications = NotificationController()
    /// Travaux lents de l'activation, pour que l'interface et les protections réagissent aussitôt.
    private let background = DispatchQueue(label: "ShowMode.background")

    /// Disposition choisie à la main, indépendamment du Mode Spectacle.
    private var manualLayout = false
    private var screenObserver: AnyCancellable?
    private var spaceObserver: AnyCancellable?

    // MARK: - Cycle de vie

    func start() {
        snapshot = store.load()
        restoreEverything() // Reprise après plantage : no-op si le journal est vide.
        refreshDisplays()

        screenObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screensDidChange() }
        // Un fond d'écran peut être propre à chaque Space : on le vérifie à chaque changement.
        spaceObserver = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.attempt { try self?.synchronizeWallpapers() } }
    }

    func shutdown() {
        isActive = false
        manualLayout = false
        restoreEverything()
        background.sync {}
    }

    private func screensDidChange() {
        refreshDisplays()
        if isActive || manualLayout {
            synchronize()
        } else if !snapshot.isEmpty {
            restoreEverything() // Un écran absent à la désactivation vient de revenir.
        } else {
            attempt { try synchronizeWallpapers() }
        }
    }

    // MARK: - Actions de l'interface

    func setActive(_ active: Bool) {
        lastError = nil
        isActive = active
        if active {
            synchronize()
        } else {
            manualLayout = false
            restoreEverything()
        }
    }

    func update(_ keyPath: WritableKeyPath<ShowOptions, Bool>, to value: Bool) {
        lastError = nil
        options[keyPath: keyPath] = value
        options.save()
        guard isActive else { return }
        if keyPath == \.diagonalLayout {
            // L'option reprend la main sur une disposition placée à la main.
            manualLayout = false
            attempt { try revertLayout() }
        }
        synchronize()
    }

    func setIdleCursorDelay(_ seconds: Int) {
        options.idleCursorDelay = seconds
        options.save()
        if isActive { synchronize() }
    }

    func isDisplayEnabled(_ display: ExternalDisplay) -> Bool {
        !options.disabledDisplayUUIDs.contains(display.uuid)
    }

    func setDisplay(_ display: ExternalDisplay, enabled: Bool) {
        lastError = nil
        if enabled {
            options.disabledDisplayUUIDs.remove(display.uuid)
        } else {
            options.disabledDisplayUUIDs.insert(display.uuid)
        }
        options.save()
        guard isActive else { return }
        // La diagonale est recalculée pour la nouvelle liste d'écrans.
        if !manualLayout { attempt { try revertLayout() } }
        synchronize()
    }

    func placeDiagonally() {
        lastError = nil
        attempt {
            try recordLayoutIfNeeded()
            manualLayout = true
            try displayManager.placeDiagonally(showDisplays.map(\.id))
        }
    }

    /// Déplace un écran depuis l'éditeur. La position est restaurée avec le reste, sauf si elle est conservée.
    @discardableResult
    func moveDisplay(_ id: CGDirectDisplayID, to origin: CGPoint) -> Bool {
        lastError = nil
        attempt {
            try recordLayoutIfNeeded()
            manualLayout = true
            try displayManager.setOrigins([id: origin])
        }
        refreshDisplays()
        return lastError == nil
    }

    func restoreLayout() {
        lastError = nil
        manualLayout = false
        if isActive { update(\.diagonalLayout, to: false) }
        attempt { try revertLayout() }
    }

    /// Fait de la disposition actuelle la nouvelle référence, conservée après ShowMode.
    func keepCurrentLayout() {
        lastError = nil
        attempt {
            let origins = Dictionary(uniqueKeysWithValues: arrangement.map { ($0.id, $0.bounds.origin) })
            try displayManager.setOrigins(origins, permanently: true)
            if isActive && options.diagonalLayout {
                options.diagonalLayout = false
                options.save()
            }
            manualLayout = false
            try record { $0.displayOrigins = nil }
        }
    }

    // MARK: - Application de l'état voulu

    private func synchronize() {
        // D'abord ce qui protège l'image et ne coûte rien.
        let showIDs = Set(showDisplays.map(\.id))
        cursor.forbiddenDisplayIDs = isActive && options.confineCursor ? showIDs : []
        cursor.idleHideDelay = isActive && options.hideIdleCursor ? TimeInterval(options.idleCursorDelay) : nil
        blackout.show(on: isActive && options.blackoutWindow ? showIDs : [])
        attempt { isActive && options.blockNotifications ? try applyNotificationPause() : try revertNotificationPause() }
        attempt { isActive && options.hideMenuBar ? try applyMenuBar() : try revertMenuBar() }
        attempt { isActive && options.hideDock ? try applyDock() : try revertDock() }
        attempt { isActive && options.hideDesktopIcons ? try applyDesktopIcons() : try revertDesktopIcons() }
        attempt { try synchronizeWallpapers() }
        attempt { isActive && options.diagonalLayout || manualLayout ? try applyDiagonalLayout() : try revertLayout() }
        attempt { isActive && options.disableGestures ? try applyGestures() : try revertGestures() }
        attempt { isActive && options.muteAlertSounds ? try applyAlertMute() : try revertAlertMute() }
    }

    /// Lance un travail lent en arrière-plan. Les restaurations attendent sa fin (`background.sync`).
    private func runInBackground(_ work: @escaping () throws -> Void) {
        background.async {
            do {
                try work()
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in self?.lastError = message }
            }
        }
    }

    private func restoreEverything() {
        blackout.hide()
        cursor.forbiddenDisplayIDs = []
        cursor.idleHideDelay = nil
        attempt { try revertLayout() }
        attempt { try revertMenuBar() }
        attempt { try revertDock() }
        attempt { try revertDesktopIcons() }
        attempt { try revertGestures() }
        attempt { try synchronizeWallpapers() }
        attempt { try revertNotificationPause() }
        attempt { try revertAlertMute() }
        refreshDisplays()
    }

    /// Enregistre le journal avant de modifier le système.
    private func record(_ change: (inout SystemSnapshot) -> Void) throws {
        change(&snapshot)
        try store.save(snapshot)
    }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Disposition

    /// Écrans externes connectés et cochés pour le spectacle.
    private var showDisplays: [ExternalDisplay] {
        displays.filter(isDisplayEnabled)
    }

    private func recordLayoutIfNeeded() throws {
        guard snapshot.displayOrigins == nil else { return }
        let origins = displayManager.currentOrigins()
        try record { $0.displayOrigins = origins }
    }

    private func applyDiagonalLayout() throws {
        guard snapshot.displayOrigins == nil, !showDisplays.isEmpty else { return }
        try recordLayoutIfNeeded()
        let manager = displayManager
        let targets = showDisplays.map(\.id)
        // Les fenêtres et le curseur suivent via la notification de changement d'écran.
        runInBackground { try manager.placeDiagonally(targets) }
    }

    private func revertLayout() throws {
        background.sync {}
        guard let origins = snapshot.displayOrigins else { return }
        let isComplete = try displayManager.restore(origins)
        // Écran débranché : on garde l'entrée pour restaurer à son retour.
        if isComplete { try record { $0.displayOrigins = nil } }
    }

    // MARK: - Barre des menus, Dock et icônes

    private func applyMenuBar() throws {
        guard snapshot.menuBarHidden == nil else { return }
        let saved = SystemSnapshot.SavedDefault(value: systemDefaults.read(.menuBarHidden))
        try record { $0.menuBarHidden = saved }
        try systemDefaults.write(.menuBarHidden, value: true, previous: saved.value)
    }

    private func revertMenuBar() throws {
        guard let saved = snapshot.menuBarHidden else { return }
        try systemDefaults.write(.menuBarHidden, value: saved.value, previous: systemDefaults.read(.menuBarHidden))
        try record { $0.menuBarHidden = nil }
    }

    private func applyDock() throws {
        guard snapshot.dockAutohide == nil else { return }
        let saved = SystemSnapshot.SavedDefault(value: systemDefaults.read(.dockAutohide))
        try record { $0.dockAutohide = saved }
        try systemDefaults.write(.dockAutohide, value: true, previous: saved.value)
    }

    private func revertDock() throws {
        guard let saved = snapshot.dockAutohide else { return }
        try systemDefaults.write(.dockAutohide, value: saved.value, previous: systemDefaults.read(.dockAutohide))
        try record { $0.dockAutohide = nil }
    }

    private func applyDesktopIcons() throws {
        guard snapshot.createDesktop == nil else { return }
        let saved = SystemSnapshot.SavedDefault(value: systemDefaults.read(.createDesktop))
        try record { $0.createDesktop = saved }
        try systemDefaults.write(.createDesktop, value: false, previous: saved.value)
    }

    private func revertDesktopIcons() throws {
        guard let saved = snapshot.createDesktop else { return }
        try systemDefaults.write(.createDesktop, value: saved.value, previous: systemDefaults.read(.createDesktop))
        try record { $0.createDesktop = nil }
    }

    // MARK: - Gestes

    private func applyGestures() throws {
        guard snapshot.gestures == nil else { return }
        let saved = gestures.capture()
        try record { $0.gestures = saved }
        let gestures = gestures
        runInBackground { try gestures.disable(saved) }
    }

    private func revertGestures() throws {
        background.sync {}
        guard let saved = snapshot.gestures else { return }
        try gestures.restore(saved)
        try record { $0.gestures = nil }
    }

    // MARK: - Fond d'écran

    /// Compare l'état réel de chaque écran à l'état voulu : un fond noir resté en place
    /// (plantage, écran débranché, autre Space) est réparé dès que possible.
    private func synchronizeWallpapers() throws {
        let wanted = Set(isActive && options.blackWallpaper ? showDisplays.map(\.uuid) : [])
        for display in displayManager.arrangedDisplays() {
            if wanted.contains(display.uuid) {
                try wallpaper.setBlack(displayID: display.id, uuid: display.uuid)
            } else {
                try wallpaper.restoreIfBlack(displayID: display.id, uuid: display.uuid)
            }
        }
    }

    // MARK: - Notifications

    private func applyNotificationPause() throws {
        guard snapshot.notificationsPaused == nil else { return }
        try record { $0.notificationsPaused = true }
        try notifications.pause()
    }

    private func revertNotificationPause() throws {
        guard snapshot.notificationsPaused != nil else { return }
        try notifications.resume()
        try record { $0.notificationsPaused = nil }
    }

    private func applyAlertMute() throws {
        guard snapshot.alertVolume == nil else { return }
        // Volume déjà à 0 : rien à lancer. Sinon, la lecture passe par un script, plus lent.
        if notifications.isAlertVolumeZero {
            try record { $0.alertVolume = 0 }
            return
        }
        let notifications = notifications
        background.async {
            guard let volume = notifications.alertVolume() else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.options.muteAlertSounds, self.snapshot.alertVolume == nil else { return }
                self.attempt { try self.record { $0.alertVolume = volume } }
                self.runInBackground { try notifications.setAlertVolume(0) }
            }
        }
    }

    private func revertAlertMute() throws {
        background.sync {}
        guard let volume = snapshot.alertVolume else { return }
        if volume != 0 { try notifications.setAlertVolume(volume) }
        try record { $0.alertVolume = nil }
    }

    // MARK: - Écrans

    private func refreshDisplays() {
        displays = displayManager.externalDisplays()
        arrangement = displayManager.arrangedDisplays()
    }
}
