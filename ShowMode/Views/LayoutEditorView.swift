import SwiftUI

/// Disposition des écrans par glisser-déposer. L'écran principal reste la référence, en (0, 0).
struct LayoutEditorView: View {
    @ObservedObject var controller: ShowModeController
    @State private var dragged: CGDirectDisplayID?
    @State private var dragOffset = CGSize.zero
    /// Position déposée, affichée jusqu'à ce que macOS confirme la nouvelle disposition.
    @State private var pendingMove: (id: CGDirectDisplayID, origin: CGPoint)?

    private let canvasSize = CGSize(width: 560, height: 340)
    private let margin: CGFloat = 24
    /// Distance d'aimantation, en points d'écran.
    private let snapDistance: CGFloat = 150
    private let canvasSpace = "layoutCanvas"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            canvas
            Text("Faites glisser un écran pour le déplacer. Cette disposition est annulée à la désactivation du Mode Spectacle, sauf si vous la conservez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Placer en diagonale") { controller.placeDiagonally() }
                    .disabled(controller.displays.isEmpty)
                Button("Restaurer la disposition d'origine") { controller.restoreLayout() }
                    .disabled(!controller.hasLayoutToRestore)
                Spacer()
                Button("Conserver cette disposition") { controller.keepCurrentLayout() }
                    .disabled(!controller.hasLayoutToRestore)
            }
        }
        .padding(16)
        .frame(width: canvasSize.width + 32)
    }

    private var canvas: some View {
        let scale = canvasScale
        let offset = canvasOffset(scale: scale)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor))
            ForEach(controller.arrangement) { display in
                displayTile(display, scale: scale)
                    .position(
                        x: bounds(of: display).midX * scale + offset.x + (dragged == display.id ? dragOffset.width : 0),
                        y: bounds(of: display).midY * scale + offset.y + (dragged == display.id ? dragOffset.height : 0)
                    )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
        .coordinateSpace(name: canvasSpace)
        .onChange(of: controller.arrangement) { _ in pendingMove = nil }
    }

    private func displayTile(_ display: ArrangedDisplay, scale: CGFloat) -> some View {
        let isShowDisplay = controller.displays.contains { $0.id == display.id && controller.isDisplayEnabled($0) }
        return VStack(spacing: 2) {
            Text(display.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            Text(display.isMain ? LocalizedStringKey("Principal") : isShowDisplay ? LocalizedStringKey("Spectacle") : LocalizedStringKey("Non utilisé"))
                .font(.caption2)
        }
        .padding(4)
        .foregroundStyle(.white)
        .frame(width: display.bounds.width * scale, height: display.bounds.height * scale)
        .background(RoundedRectangle(cornerRadius: 4).fill(display.isMain ? Color.gray : isShowDisplay ? Color.teal : Color.secondary))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.5), lineWidth: 1))
        .gesture(display.isMain ? nil : drag(display, scale: scale))
    }

    private func drag(_ display: ArrangedDisplay, scale: CGFloat) -> some Gesture {
        // Mesuré dans le canevas : en coordonnées locales, la tuile qui bouge fausserait le déplacement.
        DragGesture(coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                dragged = display.id
                dragOffset = value.translation
            }
            .onEnded { value in
                let proposed = CGPoint(
                    x: bounds(of: display).minX + value.translation.width / scale,
                    y: bounds(of: display).minY + value.translation.height / scale
                )
                dragged = nil
                dragOffset = .zero
                guard let origin = snapped(proposed, for: display) else { return }
                pendingMove = (display.id, origin)
                if !controller.moveDisplay(display.id, to: origin) { pendingMove = nil }
            }
    }

    /// Aligne l'écran sur les bords voisins. `nil` si la position recouvre un autre écran.
    private func snapped(_ origin: CGPoint, for display: ArrangedDisplay) -> CGPoint? {
        let others = controller.arrangement.filter { $0.id != display.id }.map(bounds(of:))
        let size = display.bounds.size
        func nearest(_ value: CGFloat, _ candidates: [CGFloat]) -> CGFloat {
            guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(best - value) <= snapDistance else { return value }
            return best
        }
        let x = nearest(origin.x, others.flatMap { [$0.minX, $0.maxX, $0.minX - size.width, $0.maxX - size.width] })
        let y = nearest(origin.y, others.flatMap { [$0.minY, $0.maxY, $0.minY - size.height, $0.maxY - size.height] })
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        return others.contains { $0.intersects(frame.insetBy(dx: 1, dy: 1)) } ? nil : frame.origin
    }

    private func bounds(of display: ArrangedDisplay) -> CGRect {
        guard let pendingMove, pendingMove.id == display.id else { return display.bounds }
        return CGRect(origin: pendingMove.origin, size: display.bounds.size)
    }

    private var contentBounds: CGRect {
        controller.arrangement.reduce(CGRect.null) { $0.union(bounds(of: $1)) }
    }

    private var canvasScale: CGFloat {
        let bounds = contentBounds
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return 0.1 }
        return min((canvasSize.width - margin * 2) / bounds.width, (canvasSize.height - margin * 2) / bounds.height)
    }

    private func canvasOffset(scale: CGFloat) -> CGPoint {
        let bounds = contentBounds
        guard !bounds.isNull else { return .zero }
        return CGPoint(
            x: (canvasSize.width - bounds.width * scale) / 2 - bounds.minX * scale,
            y: (canvasSize.height - bounds.height * scale) / 2 - bounds.minY * scale
        )
    }
}
