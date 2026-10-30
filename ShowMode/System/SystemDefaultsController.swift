import Foundation

/// Préférences de la barre des menus, du Dock et du Finder, modifiées via `defaults` puis appliquées par relance du processus ou notification.
struct SystemDefaultsController {
    struct Setting {
        let domain: String
        let key: String
        var process: String? = nil
        var notification: String? = nil
        /// Valeur effective de macOS quand la clé n'existe pas.
        let systemDefault: Bool

        static let menuBarHidden = Setting(
            domain: "NSGlobalDomain", key: "_HIHideMenuBar",
            notification: "AppleInterfaceMenuBarHidingChangedNotification", systemDefault: false
        )
        static let dockAutohide = Setting(domain: "com.apple.dock", key: "autohide", process: "Dock", systemDefault: false)
        static let createDesktop = Setting(domain: "com.apple.finder", key: "CreateDesktop", process: "Finder", systemDefault: true)
    }

    private let defaultsPath = "/usr/bin/defaults"

    func read(_ setting: Setting) -> Bool? {
        guard let result = try? Shell.run(defaultsPath, ["read", setting.domain, setting.key]), result.succeeded else {
            return nil
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    /// `value == nil` supprime la clé. Le processus n'est relancé que si l'effet change.
    func write(_ setting: Setting, value: Bool?, previous: Bool?) throws {
        let arguments = value.map { ["write", setting.domain, setting.key, "-bool", $0 ? "true" : "false"] }
            ?? ["delete", setting.domain, setting.key]
        if value != previous {
            let result = try Shell.run(defaultsPath, arguments)
            if !result.succeeded {
                throw Shell.Failure(message: String(localized: "Écriture de \(setting.key) impossible : \(result.output)"))
            }
        }
        if (value ?? setting.systemDefault) != (previous ?? setting.systemDefault) {
            if let process = setting.process {
                // Code de sortie ignoré : le processus peut déjà être arrêté.
                try Shell.run("/usr/bin/killall", [process])
            }
            if let notification = setting.notification {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(notification), object: nil, userInfo: nil, deliverImmediately: true
                )
            }
        }
    }
}
