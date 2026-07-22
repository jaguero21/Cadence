# Reduce Motion audit — design

## Context

Cadence uses SF Symbol bounce effects and asymmetric slide transitions across
onboarding, the daily log flow, and the weekly review flow. Only
`AmbientMeshBackground` currently checks `accessibilityReduceMotion`
(freezing its drift). A UI-code audit (see chat history, 2026-07-16) found 6
other call sites across 4 files that never check the setting. Cadence's own
`CLAUDE.md` treats accessibility on custom controls as non-optional given the
app's above-average-accessibility-need user base — this closes that gap for
motion specifically.

Scope is intentionally narrow: only the two clearly-decorative motion
categories below. Spring-driven state transitions (mood/step selection,
`withAnimation(CadenceAnimation.spring)`) and numeric/content-transition
counters (`.contentTransition(.numericText())`, `.symbolEffect(.replace)`)
are explicitly out of scope for this pass.

## Audit findings

**Slide transitions** (2 sites) — `.transition(.asymmetric(insertion: .move(edge: .trailing)..., removal: .move(edge: .leading)...))`:
- `Cadence/Features/DailyLog/LogInputFlow.swift:79` — step-to-step transition
- `Cadence/Features/Onboarding/OnboardingView.swift:21` — page-to-page transition

**Decorative symbol bounces** (4 sites) — `.symbolEffect(.bounce, ...)`:
- `Cadence/Shared/Components/MetricSlider.swift:88` — `StreakBadge` milestone flame, `options: .repeat(2)` (genuinely repeating)
- `Cadence/Features/DailyLog/LogInputFlow.swift:561` — done-step checkmark, one-shot (`value: 1`)
- `Cadence/Features/Onboarding/OnboardingView.swift:164` — page icon, one-shot (`value: iconAppeared`, toggled on `onAppear`)
- `Cadence/Features/WeeklyReview/ReviewFlowView.swift:196` — completion checkmark, one-shot (`value: 1`)

All four bounces communicate "this already happened" via accompanying text
or a static icon — the bounce itself is decorative, not the sole carrier of
meaning, so it's safe to drop entirely under Reduce Motion rather than
substitute another motion effect.

## Design

Two additions to `Cadence/Shared/Extensions/View+Extensions.swift`, following
this file's existing role as the home for cross-cutting view modifiers
(`.readableColumn()`, `.adaptableTabBar()`):

```swift
extension View {
    /// Applies `.symbolEffect(.bounce, ...)` unless Reduce Motion is on, in
    /// which case the bounce is skipped entirely (the icon/text alone still
    /// carries the meaning — see design doc for why no substitute effect is needed).
    @ViewBuilder
    func cadenceSymbolBounce(value: some Equatable, repeating count: Int? = nil) -> some View {
        modifier(CadenceSymbolBounceModifier(trigger: value, repeatCount: count))
    }
}

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

extension AnyTransition {
    /// The step/page slide transition, or a plain crossfade when Reduce
    /// Motion is on.
    static func cadenceStepSlide(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }
}
```

### Call-site changes

1. `LogInputFlow.swift:79` — add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the view, swap the inline `.transition(.asymmetric(...))` for `.transition(.cadenceStepSlide(reduceMotion: reduceMotion))`.
2. `OnboardingView.swift:21` — same swap; `OnboardingView` also needs the environment property added.
3. `MetricSlider.swift:88` (`StreakBadge`) — swap `.symbolEffect(.bounce, options: .repeat(2), value: isMilestone)` for `.cadenceSymbolBounce(value: isMilestone, repeating: 2)`.
4. `LogInputFlow.swift:561` — swap `.symbolEffect(.bounce, value: 1)` for `.cadenceSymbolBounce(value: 1)`.
5. `OnboardingView.swift:164` — swap `.symbolEffect(.bounce, value: iconAppeared)` for `.cadenceSymbolBounce(value: iconAppeared)`.
6. `ReviewFlowView.swift:196` — swap `.symbolEffect(.bounce, value: 1)` for `.cadenceSymbolBounce(value: 1)`.

No other call sites change. Springs and content transitions are untouched.

## Testing

No new unit tests — this is view-layer motion presentation, not logic with
business value (per this project's testing convention of prioritizing tests
for pattern/insight/save logic over UI glue). Verified manually instead:
Settings → Accessibility → Motion → Reduce Motion, then walk onboarding, a
full daily log, and a weekly review, confirming crossfades replace slides
and no bounce fires anywhere in scope. Re-check with Reduce Motion off to
confirm existing behavior is unchanged.

## Out of scope

- `withAnimation(CadenceAnimation.spring)` state transitions (mood/step
  selection, dot indicator, view-model step advances)
- `.contentTransition(.numericText())` / `.contentTransition(.symbolEffect(.replace))`
  counters (sliders, widget)
- Any change to `CadenceAnimation`, `AmbientMeshBackground` (already handled)
