import Foundation

/// Coupe les bannières en mettant Notification Center en pause : aucune API publique ne le permet,
/// et le contrôle direct de Focus est refusé aux apps tierces. Les bannières en attente s'affichent à la reprise.
final class NotificationController {
    private let processName = "NotificationCenter"
    private var timer: Timer?
    private var watchdog: Process?

    func pause() throws {
        try signal("-STOP")
        startWatchdog()
        // macOS peut relancer le processus : on le remet en pause.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            try? self?.signal("-STOP")
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func resume() throws {
        timer?.invalidate()
        timer = nil
        watchdog?.terminate()
        watchdog = nil
        try signal("-CONT")
    }

    var isAlertVolumeZero: Bool {
        let value = CFPreferencesCopyAppValue("com.apple.sound.beep.volume" as CFString, kCFPreferencesAnyApplication)
        return (value as? NSNumber)?.doubleValue == 0
    }

    func alertVolume() -> Int? {
        let result = try? Shell.run("/usr/bin/osascript", ["-e", "alert volume of (get volume settings)"])
        return result.flatMap { Int($0.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Volume des alertes uniquement : le son de sortie, donc celui de QLab, ne change pas.
    func setAlertVolume(_ volume: Int) throws {
        let result = try Shell.run("/usr/bin/osascript", ["-e", "set volume alert volume \(volume)"])
        if !result.succeeded {
            throw Shell.Failure(message: String(localized: "Réglage du volume des alertes impossible : \(result.output)"))
        }
    }

    private func signal(_ flag: String) throws {
        // Code de sortie ignoré : le processus peut être momentanément absent.
        try Shell.run("/usr/bin/pkill", [flag, "-x", processName])
    }

    /// Processus indépendant : si ShowMode meurt (plantage, arrêt depuis Xcode), les notifications reprennent.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let appPID = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(appPID) 2>/dev/null; do sleep 2; done; /usr/bin/pkill -CONT -x \(processName)"]
        try? process.run()
        watchdog = process
    }
}
