import SwiftUI

// Applies `.symbolEffect(.bounce, ...)` unless Reduce Motion is on, in which
// case the bounce is skipped entirely — the icon/text next to it already
// carries the meaning (e.g. "Log complete!"), so no substitute motion effect
// is needed. See docs/superpowers/specs/2026-07-16-reduce-motion-audit-design.md.
private struct CadenceSymbolBounceModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger
    let repeatCount: Int?

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if let repeatCount {
            content.symbolEffect(.bounce, options: .repeat(repeatCount), value: trigger)
        } else {
            content.symbolEffect(.bounce, value: trigger)
        }
    }
}

extension View {
    @ViewBuilder
    func cadenceSymbolBounce(value: some Equatable, repeating: Int? = nil) -> some View {
        modifier(CadenceSymbolBounceModifier(trigger: value, repeatCount: repeating))
    }
}

extension View {
    func cadenceCard() -> some View {
        self
            .padding(CadenceLayout.cardPadding)
            .background(CadenceColor.cardBG, in: RoundedRectangle(cornerRadius: CadenceLayout.cardCornerRadius))
    }

    // Liquid Glass on iOS 26, the classic bar material before it. Used for the
    // floating control bars (step indicator, flow nav) so they pick up the
    // system's current-year chrome without forking layouts.
    @ViewBuilder
    func glassBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect)
        } else {
            self.background(.bar)
        }
    }

    // Caps a scrolling card column at a readable width and centers it, so
    // iPad (and landscape) doesn't stretch phone-designed cards edge to edge.
    // No-op wherever the proposed width is already narrower.
    func readableColumn(maxWidth: CGFloat = CadenceLayout.readableColumnWidth) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    // iPad gets the adaptable tab bar (iOS 18): a top bar the user can switch
    // to a sidebar. iPhone and earlier systems keep the classic bottom bar.
    @ViewBuilder
    func adaptableTabBar() -> some View {
        if #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }

    // Tab bar tucks away while scrolling content (iOS 26); no-op earlier.
    @ViewBuilder
    func minimizableTabBar() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    // Zoom transition pair (iOS 18): mark the tapped cell as the source and
    // the presented detail as the destination; earlier systems keep the
    // standard sheet slide.
    @ViewBuilder
    func zoomTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
            self
        }
    }
}

extension AnyTransition {
    // The step/page slide transition, or a plain crossfade when Reduce
    // Motion is on. See docs/superpowers/specs/2026-07-16-reduce-motion-audit-design.md.
    static func cadenceStepSlide(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }
}

extension Color {
    static func metricColor(for value: Int, max: Int = 10, inverted: Bool = false) -> Color {
        let normalized = Double(value) / Double(max)
        let score = inverted ? 1.0 - normalized : normalized
        if score > 0.7 { return CadenceColor.successGreen }
        if score > 0.4 { return CadenceColor.energyOrange }
        return CadenceColor.stressRed
    }
}

extension Date {
    var startOfWeek: Date {
        let cal = Calendar.current
        return cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date ?? self
    }

    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .weekOfYear)
    }
}
