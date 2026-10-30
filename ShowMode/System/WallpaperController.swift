import AppKit

/// Les fonds d'origine sont gardés dans leur propre fichier, jusqu'à leur restauration effective.
/// Un écran affichant encore le fond noir de ShowMode peut ainsi toujours être réparé.
struct WallpaperController {
    private let workspace = NSWorkspace.shared
    private let originalsURL = AppPaths.supportDirectory.appendingPathComponent("wallpapers.json")
    private let blackURL = AppPaths.supportDirectory.appendingPathComponent("black.png")

    func setBlack(displayID: CGDirectDisplayID, uuid: String) throws {
        guard let screen = NSScreen.screen(for: displayID), !isBlack(screen) else { return }
        if let original = capture(screen, uuid: uuid) {
            var originals = loadOriginals()
            originals[uuid] = original
            try save(originals)
        }
        try workspace.setDesktopImageURL(try blackImageURL(), for: screen, options: [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            .allowClipping: true,
            .fillColor: NSColor.black,
        ])
    }

    func restoreIfBlack(displayID: CGDirectDisplayID, uuid: String) throws {
        guard let screen = NSScreen.screen(for: displayID), isBlack(screen) else { return }
        var originals = loadOriginals()
        // Original perdu : on reprend le fond d'un autre écran plutôt que de laisser du noir.
        guard let saved = originals[uuid] ?? fallback(uuid: uuid) else { return }
        try apply(saved, to: screen)
        originals[uuid] = nil
        try save(originals)
    }

    private func isBlack(_ screen: NSScreen) -> Bool {
        workspace.desktopImageURL(for: screen)?.standardizedFileURL.path == blackURL.standardizedFileURL.path
    }

    private func fallback(uuid: String) -> SystemSnapshot.Wallpaper? {
        NSScreen.screens.first { !isBlack($0) }.flatMap { capture($0, uuid: uuid) }
    }

    private func capture(_ screen: NSScreen, uuid: String) -> SystemSnapshot.Wallpaper? {
        guard let url = workspace.desktopImageURL(for: screen) else { return nil }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let fillColor = options[.fillColor] as? NSColor
        return SystemSnapshot.Wallpaper(
            displayUUID: uuid,
            imageURL: url,
            scaling: (options[.imageScaling] as? NSNumber)?.uintValue,
            allowClipping: (options[.allowClipping] as? NSNumber)?.boolValue,
            fillColorData: fillColor.flatMap {
                try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
            }
        )
    }

    private func apply(_ saved: SystemSnapshot.Wallpaper, to screen: NSScreen) throws {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = saved.scaling { options[.imageScaling] = scaling }
        if let clipping = saved.allowClipping { options[.allowClipping] = clipping }
        if let data = saved.fillColorData,
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            options[.fillColor] = color
        }
        try workspace.setDesktopImageURL(restorableURL(for: saved.imageURL), for: screen, options: options)
    }

    /// macOS décrit un fond dynamique par son image fixe : on retrouve le fond système d'origine
    /// quand il existe, pour qu'il reste dynamique après la restauration.
    private func restorableURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let dynamic = URL(fileURLWithPath: "/System/Library/Desktop Pictures/\(name).madesktop")
        return FileManager.default.fileExists(atPath: dynamic.path) ? dynamic : url
    }

    private func loadOriginals() -> [String: SystemSnapshot.Wallpaper] {
        guard let data = try? Data(contentsOf: originalsURL),
              let originals = try? JSONDecoder().decode([String: SystemSnapshot.Wallpaper].self, from: data) else {
            return [:]
        }
        return originals
    }

    private func save(_ originals: [String: SystemSnapshot.Wallpaper]) throws {
        try JSONEncoder().encode(originals).write(to: originalsURL, options: .atomic)
    }

    /// Image #000000 générée une fois dans Application Support.
    private func blackImageURL() throws -> URL {
        if FileManager.default.fileExists(atPath: blackURL.path) { return blackURL }

        let size = 16
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw Shell.Failure(message: String(localized: "Création du fond noir impossible."))
        }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Shell.Failure(message: String(localized: "Création du fond noir impossible."))
        }
        try png.write(to: blackURL, options: .atomic)
        return blackURL
    }
}
