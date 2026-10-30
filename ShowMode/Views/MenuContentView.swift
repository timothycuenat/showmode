import SwiftUI

struct MenuContentView: View {
    @ObservedObject var controller: ShowModeController
    let openLayoutEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            displaySection
            Divider()
            desktopSection
            Divider()
            cursorSection
            Divider()
            notificationSection
            Divider()
            iconSection
            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button("Quitter l'application") { NSApp.terminate(nil) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mode Spectacle").font(.headline)
                Text(controller.isActive ? LocalizedStringKey("Actif") : LocalizedStringKey("Inactif"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Mode Spectacle", isOn: Binding(
                get: { controller.isActive },
                set: { controller.setActive($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Écrans du spectacle")
            if controller.displays.isEmpty {
                Text("Aucun écran externe détecté")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.displays) { display in
                Toggle(display.name, isOn: Binding(
                    get: { controller.isDisplayEnabled(display) },
                    set: { controller.setDisplay(display, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
            }
            Button("Gérer la disposition des écrans…", action: openLayoutEditor)
            .controlSize(.small)
        }
    }

    private var desktopSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Options")
            option("Masquer la barre des menus", \.hideMenuBar)
            option("Masquer le Dock", \.hideDock)
            option("Masquer les icônes du bureau", \.hideDesktopIcons)
            option("Positionnement en diagonale", \.diagonalLayout)
            option("Fond d'écran noir sur les écrans cochés", \.blackWallpaper)
            option("Fenêtre Blackout de secours", \.blackoutWindow)
            option("Couper les gestes Mission Control et Spaces", \.disableGestures)
        }
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Curseur")
            option("Interdire les écrans cochés", \.confineCursor)
            option("Masquer après inactivité", \.hideIdleCursor)
            Stepper(
                "Délai : \(controller.options.idleCursorDelay) s",
                value: Binding(
                    get: { controller.options.idleCursorDelay },
                    set: { controller.setIdleCursorDelay($0) }
                ),
                in: 1...60
            )
            .disabled(!controller.options.hideIdleCursor)
            .padding(.leading, 20)
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Notifications")
            option("Couper les bannières de notification", \.blockNotifications)
            option("Couper les sons d'alerte", \.muteAlertSounds)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Icône")
            option("Activer ou désactiver d'un clic sur l'icône", \.toggleOnIconClick)
            if controller.options.toggleOnIconClick {
                Text("Clic droit sur l'icône pour rouvrir ce menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func option(_ title: LocalizedStringKey, _ keyPath: WritableKeyPath<ShowOptions, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { controller.options[keyPath: keyPath] },
            set: { controller.update(keyPath, to: $0) }
        ))
        .toggleStyle(.checkbox)
    }
}
