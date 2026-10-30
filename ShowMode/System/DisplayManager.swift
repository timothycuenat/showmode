import AppKit
import CoreGraphics

struct ExternalDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }
}

/// Écran actif, tel qu'affiché dans l'éditeur de disposition.
struct ArrangedDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
    let isMain: Bool
}

struct DisplayManager {
    func arrangedDisplays() -> [ArrangedDisplay] {
        onlineDisplays()
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .compactMap { id in
                guard let uuid = uuid(for: id) else { return nil }
                let name = NSScreen.screen(for: id)?.localizedName ?? String(localized: "Écran \(Int(id))")
                return ArrangedDisplay(id: id, uuid: uuid, name: name, bounds: CGDisplayBounds(id), isMain: id == CGMainDisplayID())
            }
    }

    func externalDisplays() -> [ExternalDisplay] {
        onlineDisplays()
            .filter { $0 != CGMainDisplayID() && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .compactMap { id in
                guard let uuid = uuid(for: id) else { return nil }
                let name = NSScreen.screen(for: id)?.localizedName ?? String(localized: "Écran \(Int(id))")
                return ExternalDisplay(id: id, uuid: uuid, name: name)
            }
    }

    func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        onlineDisplays().first { self.uuid(for: $0) == uuid }
    }

    func currentOrigins() -> [String: SystemSnapshot.Origin] {
        var origins: [String: SystemSnapshot.Origin] = [:]
        for id in onlineDisplays() {
            guard let uuid = uuid(for: id) else { continue }
            let origin = CGDisplayBounds(id).origin
            origins[uuid] = .init(x: origin.x, y: origin.y)
        }
        return origins
    }

    /// Place les écrans en escalier, en bas à droite des autres : seuls les coins se touchent,
    /// le curseur ne peut donc pas y glisser par accident.
    func placeDiagonally(_ targets: [CGDirectDisplayID]) throws {
        let others = onlineDisplays().filter { !targets.contains($0) }
        var union = others.reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
        guard !union.isNull else { return }
        var changes: [(CGDirectDisplayID, Int32, Int32)] = []
        for id in targets {
            let bounds = CGDisplayBounds(id)
            changes.append((id, Int32(union.maxX), Int32(union.maxY)))
            union = union.union(CGRect(x: union.maxX, y: union.maxY, width: bounds.width, height: bounds.height))
        }
        try configure(changes)
    }

    func setOrigins(_ origins: [CGDirectDisplayID: CGPoint], permanently: Bool = false) throws {
        try configure(origins.map { ($0.key, Int32($0.value.x), Int32($0.value.y)) }, option: permanently ? .permanently : .forSession)
    }

    /// Retourne `false` si un écran enregistré est absent : la restauration reste à terminer.
    func restore(_ origins: [String: SystemSnapshot.Origin]) throws -> Bool {
        var changes: [(CGDirectDisplayID, Int32, Int32)] = []
        var isComplete = true
        for (uuid, origin) in origins {
            guard let id = displayID(forUUID: uuid) else {
                isComplete = false
                continue
            }
            if CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay {
                changes.append((id, Int32(origin.x), Int32(origin.y)))
            }
        }
        try configure(changes)
        return isComplete
    }

    /// `.forSession` : en dernier recours, une déconnexion rétablit la disposition enregistrée par macOS.
    private func configure(_ changes: [(CGDirectDisplayID, Int32, Int32)], option: CGConfigureOption = .forSession) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        for (id, x, y) in changes {
            let result = CGConfigureDisplayOrigin(config, id, x, y)
            if result != .success {
                CGCancelDisplayConfiguration(config)
                try check(result)
            }
        }
        try check(CGCompleteDisplayConfiguration(config, option))
    }

    private func check(_ result: CGError) throws {
        if result != .success {
            throw Shell.Failure(message: String(localized: "Configuration de l'écran impossible (CGError \(Int(result.rawValue)))."))
        }
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func uuid(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
