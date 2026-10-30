import Foundation

/// Préférences de l'utilisateur, conservées d'un lancement à l'autre.
struct ShowOptions: Codable, Equatable {
    /// Écrans externes exclus du spectacle : un nouvel écran y participe par défaut.
    var disabledDisplayUUIDs: Set<String> = []
    var hideMenuBar = true
    var hideDock = true
    var hideDesktopIcons = true
    var diagonalLayout = true
    var blackWallpaper = true
    var blackoutWindow = false
    var confineCursor = true
    var hideIdleCursor = true
    var idleCursorDelay = 3
    var disableGestures = true
    var blockNotifications = true
    var muteAlertSounds = true
    /// Un clic sur l'icône bascule le mode ; le clic droit ouvre toujours le menu.
    var toggleOnIconClick = false

    private static let key = "showOptions.v3"

    /// Les clés absentes (nouvelles options) gardent leur valeur par défaut.
    static func load() -> ShowOptions {
        guard let stored = UserDefaults.standard.data(forKey: key),
              let storedValues = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let defaults = try? JSONEncoder().encode(ShowOptions()),
              let defaultValues = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaultValues.merging(storedValues) { $1 }),
              let options = try? JSONDecoder().decode(ShowOptions.self, from: merged) else {
            return ShowOptions()
        }
        return options
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
