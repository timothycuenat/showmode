import Foundation

/// Journal de ce que ShowMode a modifié, avec les valeurs d'origine.
///
/// Un champ non nil signifie « modifié, à restaurer ». Le journal est écrit sur disque
/// AVANT chaque modification : après un plantage, le lancement suivant peut tout remettre en place.
struct SystemSnapshot: Codable, Equatable {
    struct Origin: Codable, Equatable {
        var x: Double
        var y: Double
    }

    /// `value == nil` : la clé n'existait pas dans les préférences (elle sera supprimée).
    struct SavedDefault: Codable, Equatable {
        var value: Bool?
    }

    struct Wallpaper: Codable, Equatable {
        var displayUUID: String
        var imageURL: URL
        var scaling: UInt?
        var allowClipping: Bool?
        var fillColorData: Data?
    }

    /// Réglage de geste du trackpad. `value == nil` : la clé n'existait pas.
    struct GestureSetting: Codable, Equatable {
        var domain: String
        var key: String
        var value: Int?
        var isBool: Bool
    }

    /// Origine de chaque écran, indexée par UUID (les CGDirectDisplayID peuvent changer).
    var displayOrigins: [String: Origin]?
    var dockAutohide: SavedDefault?
    var createDesktop: SavedDefault?
    var menuBarHidden: SavedDefault?
    var gestures: [GestureSetting]?
    var notificationsPaused: Bool?
    var alertVolume: Int?

    var isEmpty: Bool { self == SystemSnapshot() }
}

/// Persistance du journal dans Application Support.
struct SnapshotStore {
    private let url = AppPaths.supportDirectory.appendingPathComponent("snapshot.json")

    func load() -> SystemSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SystemSnapshot.self, from: data) else {
            return SystemSnapshot()
        }
        return snapshot
    }

    func save(_ snapshot: SystemSnapshot) throws {
        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }
}

enum AppPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ShowMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}
