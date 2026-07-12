import SwiftUI

// Soft, slowly drifting mesh gradient behind "hero" surfaces — the dashboard
// and the log/review completion screens. Deliberately faint: cards must stay
// readable on top of it in both color schemes. Colors derive from CadenceColor
// so a future palette change re-skins it automatically.
//
// iOS 17 gets the flat background (MeshGradient is iOS 18+); Reduce Motion
// gets the mesh frozen at its resting phase instead of the drift animation.
struct AmbientMeshBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                if reduceMotion {
                    mesh(phase: 0)
                } else {
                    // ~12 fps is plenty for a drift this slow and keeps the
                    // continuous redraw cheap.
                    TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                        mesh(phase: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                CadenceColor.background
            }
        }
        .ignoresSafeArea()
    }

    @available(iOS 18.0, *)
    private func mesh(phase t: TimeInterval) -> some View {
        // Two incommensurate frequencies so the drift never visibly loops.
        let driftX = Float(sin(t * 0.22)) * 0.12
        let driftY = Float(cos(t * 0.17)) * 0.12
        return ZStack {
            CadenceColor.background
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + driftX, 0.5 + driftY], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    CadenceColor.moodBlue.opacity(0.16), .clear, CadenceColor.sleepPurple.opacity(0.14),
                    .clear, CadenceColor.accent.opacity(0.08), .clear,
                    CadenceColor.energyOrange.opacity(0.10), .clear, CadenceColor.moodBlue.opacity(0.12),
                ]
            )
        }
    }
}
