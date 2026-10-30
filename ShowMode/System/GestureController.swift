import Foundation

/// macOS ne permet pas de limiter Mission Control à un écran : ses gestes sont coupés à l'échelle du système.
struct GestureController {
    private let trackpadDomains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private let trackpadKeys = [
        "TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture",
        "TrackpadFourFingerHorizSwipeGesture", "TrackpadFourFingerVertSwipeGesture",
        "TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture",
    ]
    private let dockKeys = [
        "showMissionControlGestureEnabled", "showAppExposeGestureEnabled",
        "showDesktopGestureEnabled", "showLaunchpadGestureEnabled",
    ]
    private let defaultsPath = "/usr/bin/defaults"
    private let activateSettingsPath = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    func capture() -> [SystemSnapshot.GestureSetting] {
        let trackpad = trackpadDomains.flatMap { domain in
            trackpadKeys.map { setting(domain: domain, key: $0, isBool: false) }
        }
        return trackpad + dockKeys.map { setting(domain: "com.apple.dock", key: $0, isBool: true) }
    }

    func disable(_ settings: [SystemSnapshot.GestureSetting]) throws {
        for setting in settings where setting.value != 0 {
            try write(setting, value: 0)
        }
        try applyChanges()
    }

    func restore(_ settings: [SystemSnapshot.GestureSetting]) throws {
        for setting in settings where setting.value != 0 {
            try write(setting, value: setting.value)
        }
        try applyChanges()
    }

    /// Lecture directe, sans lancer un processus par clé.
    private func setting(domain: String, key: String, isBool: Bool) -> SystemSnapshot.GestureSetting {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber
        return .init(domain: domain, key: key, value: value?.intValue, isBool: isBool)
    }

    private func write(_ setting: SystemSnapshot.GestureSetting, value: Int?) throws {
        var arguments = ["delete", setting.domain, setting.key]
        if let value {
            arguments = ["write", setting.domain, setting.key]
                + (setting.isBool ? ["-bool", value == 0 ? "false" : "true"] : ["-int", String(value)])
        }
        let result = try Shell.run(defaultsPath, arguments)
        if !result.succeeded {
            throw Shell.Failure(message: String(localized: "Écriture de \(setting.key) impossible : \(result.output)"))
        }
    }

    private func applyChanges() throws {
        try Shell.run(activateSettingsPath, ["-u"])
        try Shell.run("/usr/bin/killall", ["Dock"])
    }
}
