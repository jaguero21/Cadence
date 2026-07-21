# Cadence Mascot — Design & Implementation Guide

## Overview

Cadence gets a mascot: a calm, unbothered capybara that appears in ambient,
low-stakes moments (onboarding, empty states, streaks, the Home Screen
widget). It is a companion presence, not a character with dialogue, and it
never appears anywhere the app needs to read as clinical (symptom/pain
logging, the doctor PDF).

This document covers both the mascot's design and the guide for producing
and implementing it. It also records the technical gaps found in review
(2026-07-21) and how each was resolved or explicitly deferred — see
Section 8.

## 1. Concept & Personality

- **Working name:** "Cadence the Capybara" — used in code/docs/comments
  only. In-app, it stays unnamed ("your companion") so it never competes
  with the app's own name.
- **Personality:** unbothered, patient, warm, never alarmed. On a bad
  symptom day it stays calm and present rather than looking sad or
  distressed — it accompanies a hard day, it doesn't react to it.
- **No dialogue.** Expression is conveyed through pose and setting only, no
  speech bubbles or first-person copy. This keeps it a quiet companion
  rather than a chatty gimmick competing with the app's actual UI copy —
  and it means the mascot image is always decorative rather than
  informational: nearby text carries the meaning, so every mascot image
  gets `.accessibilityHidden(true)` (see Section 6, step 6).
- **Tonal guardrail:** the capybara is additive and ambient-only. It never
  appears next to symptom severity input, pain logging, medication
  entry, or the doctor/personal PDF exports — those stay mascot-free,
  matching the existing "not medical advice" disclaimer discipline used
  for `PatternEngine` insights.
- **Priority rule:** when more than one trigger applies, the app never
  looks cheerful about a hard stretch. `.cozy` (active flare or low mood
  trend) outranks `.soaking` (streak reward) outranks `.resting` outranks
  `.welcoming`. This mirrors how `PatternEngine` sorts insights
  strongest-first rather than by detector order.

## 2. Pose Set & Trigger Rules

MVP set of 5 poses — enough variety without an unbounded art budget.

| Pose | Description | Trigger | Where it shows |
|---|---|---|---|
| `.welcoming` | Sitting up, relaxed, small welcoming gesture | No logs in the visible window (true first-time or long-lapsed user) | Onboarding welcome page; Dashboard/Insights empty state |
| `.resting` | Lounging calmly, eyes half-open | Default: has history, nothing else (`.cozy`/`.soaking`) applies — independent of whether today is logged | **Widget only** for MVP — see Section 8.2 for why this isn't a Dashboard placement |
| `.soaking` | In a hot spring (the classic capybara-onsen pose), content | Active streak ≥ `MascotThreshold.streakDaysForSoaking` (7 consecutive days) | Dashboard streak badge, streak-milestone moment, widget |
| `.cozy` | Curled up under a blanket, calm — not sad | Recent mood/energy trending low, or an active `Flare` | Dashboard/Insights/widget, in place of `.resting`/`.soaking` when it applies |
| `.sleepy` | Yawning, lying down | Evening daily-reminder notification fires (time-triggered) | **Deferred** — see Section 8.3; the evening reminder ships without a mascot image for MVP |

Priority order when multiple triggers match:
`.cozy` > `.soaking` > `.resting` > `.welcoming`.

Note: `.welcoming`'s trigger is now stated as "no logs in the visible
window" rather than "no logging history at all" — that's what the actual
Dashboard/Insights empty states check (a bounded query window, not
lifetime history), and it's the condition `MascotPoseEngine` should
actually test. See Section 8.2.

## 3. Technical Architecture

- **`MascotPose`** — new `String, CaseIterable` enum. Raw values double as
  asset names (`mascot-welcoming`, `mascot-resting`, `mascot-soaking`,
  `mascot-cozy`, `mascot-sleepy`), so rendering is `Image("mascot-\(pose
  .rawValue)")` with no separate name-mapping table — same pattern as the
  existing symptom/color name maps in `HealthKitService`.
- **`MascotPoseEngine`** — new stateless `enum` in `Cadence/Services/`,
  next to `PatternEngine.swift`. One pure function:

  ```swift
  enum MascotPoseEngine {
      static func pose(
          for logs: [DailyLogSnapshot],
          activeFlare: FlareSnapshot?,
          streakDays: Int
      ) -> MascotPose
  }
  ```

  It takes `DailyLogSnapshot`/`FlareSnapshot`, never a `@Model` across
  actors (same rule documented for `PatternEngine`), so it's usable from
  the main app, the widget extension, and (later) the notification builder
  without re-deriving logic in three places. (Changed from the original
  draft's `Flare?` to `FlareSnapshot?` — the app-side caller already has to
  snapshot it before crossing into `publishWidgetSummary`'s static context;
  taking the `@Model` type here would just move the violation one call
  deeper.)
- **Thresholds** — new constants added to the existing
  `Shared/Constants.swift` (e.g. `MascotThreshold.streakDaysForSoaking = 7`,
  `MascotThreshold.lowMoodTrendDays = 3` — 3 consecutive below-average mood
  days before `.cozy` kicks in, long enough not to flip on a single off day),
  reusing the file that already holds
  `PatternThreshold`/`ChartThreshold` rather than introducing a new
  thresholds file.
- **Assets** — vector PDFs/SVGs added to `Assets.xcassets`. Art is drawn
  as a **single flat tint region** (line work and fill are the same
  color under Template Image rendering — see Section 8.5, this is a hard
  constraint, not a style preference) so it recolors via the existing
  `CadenceColor` catalog at render time, the same way other iconography is
  tinted. If a two-tone look (darker outline, lighter fill) is wanted
  later, that needs two separately-tinted template layers per pose —
  treat as a v2 exploration, not MVP.
- **Cross-target reuse** — the widget extension and watch app can't run
  `MascotPoseEngine` directly (no SwiftData store in those processes), so
  the pose is computed on the app side and added as a new field on the
  existing `WidgetData.Summary` struct:

  ```swift
  struct Summary: Codable, Equatable {
      var date: Date
      var loggedToday: Bool
      var streak: Int
      var mascotPose: MascotPose   // new
  }
  ```

  `MascotPose` needs `Codable` in addition to `String, CaseIterable` for
  this. See Section 8.1 for exactly where this gets computed and why —
  `publishWidgetSummary` is a shared static function with more callers
  than "the Dashboard."

## 4. Surface-by-Surface Implementation

| Surface | Change |
|---|---|
| Onboarding (`OnboardingView.welcomePage`) | `.welcoming` pose added alongside the current `waveform.path.ecg.rectangle.fill` icon on the welcome page only. Rest of onboarding stays icon-based. |
| Dashboard empty state | `.welcoming` capybara illustration replaces the current generic empty-state treatment, gated on the same `logs.isEmpty` condition the view already checks. (Not `.resting` — see Section 8.2.) |
| Streak badge | `.soaking` capybara considered next to the streak counter once the threshold is hit — additive, doesn't replace the existing streak UI. **Needs a sized mock before implementation**; see Section 8.4 — `StreakBadge` is a compact single-row `HStack` today and the illustration may not fit cleanly inline. |
| Home Screen widget | `.resting`/`.soaking`/`.cozy` swapped in for "no check-in yet"/streak states, read from the new `WidgetData.Summary.mascotPose` field. This is `.resting`'s primary and, for MVP, only placement. Lock Screen/StandBy accessory families stay symbol-only (too small for the art to read). |
| Notifications | **Deferred, not MVP.** See Section 8.3 — rich notification images need a file URL, not an asset catalog name, and there's no existing code path for that in this app. The evening daily reminder stays plain-text for now. The medication reminder and Control Center check-in stay mascot-free regardless (functional/clinical, not ambient). |
| Insights tab empty state | `.welcoming`, matching Dashboard's corrected logic. Replaces the existing `ContentUnavailableView` — that native component provides VoiceOver semantics for free, so the replacement must explicitly carry an equivalent accessibility label on the empty-state container (the mascot image itself stays `.accessibilityHidden(true)` per Section 1). |

**Explicitly out of scope:** App Store icon/screenshots, marketing/website,
symptom/pain logging screens, medication logging, the doctor/personal PDF
exports, and (deferred — see Section 8.3) the notification rich attachment.

## 5. Art Production Steps

1. Draw the 5 poses as flat vector illustrations (recommend Figma or
   Illustrator) at a square artboard, consistent stroke weight and line
   style across all 5 so they read as one set.
2. Keep artwork **single-color-total**: line work and fill must resolve to
   one tint when rendered as a Template Image (see Section 8.5) — no
   gradients, no baked-in color, and no reliance on a separate outline
   color, so `CadenceColor` tinting applies cleanly in both light and dark
   mode.
3. Export each pose as PDF (preferred, matches how other vector assets in
   this catalog are handled) or SVG, at a size that stays crisp at both the
   small widget scale and the larger dashboard/onboarding scale.
4. Add each exported file to `Assets.xcassets` as an image set named
   `mascot-<pose-rawValue>` (e.g. `mascot-welcoming`), matching the
   `MascotPose` raw values exactly so `Image("mascot-\(pose.rawValue)")`
   resolves with no lookup table.
5. Set each image set's "Render As" to Template Image so `CadenceColor`
   tinting via `.foregroundStyle`/`.tint` applies the same way existing
   template icons do. Confirm each pose still reads clearly as a single
   silhouette once flattened to one color — this is the point in
   production where a two-tone design would visibly fail and need
   reworking before export.

## 6. Code Integration Steps

1. Add `MascotPose` enum (`Cadence/Models/` or `Cadence/Shared/`, wherever
   small shared enums currently live) — `String, CaseIterable, Codable`.
2. Add `MascotThreshold` constants to `Shared/Constants.swift`.
3. Write `MascotPoseEngine.pose(for:activeFlare:streakDays:)` in
   `Cadence/Services/MascotPoseEngine.swift`, implementing the priority
   order from Section 2. Unit-test it the way `PatternEngine`'s pure
   helpers are tested — table of (logs, flare, streak) → expected pose.
4. Wire `MascotPoseEngine` into `DashboardViewModel` for the Dashboard
   empty state (`.welcoming`, gated on `logs.isEmpty`) and streak badge
   (`.soaking`).
5. Add `mascotPose: MascotPose` to `WidgetData.Summary`. Widen
   `DashboardViewModel.publishWidgetSummary` to
   `publishWidgetSummary(logs: [DailyLog], flares: [Flare] = [])`, mirroring
   the `flares: [Flare] = []` default `DashboardViewModel.refresh` already
   uses. Update `refresh` to pass its own `flares` through (it already
   receives them — this is a one-line change, not a new fetch). Leave the
   other 6 call sites (`CadenceApp`, `LogInputFlow`,
   `PhoneConnectivityManager`, `CheckInIntents`, `SyncBackupSection`) on the
   default `[]` — see Section 8.1 for why that's an acceptable, temporary
   staleness rather than a bug to chase down.
6. Update the widget's `Provider`/entry view to render the mascot image
   (`.accessibilityHidden(true)`, text nearby carries the meaning) for the
   relevant families, still respecting the existing `summary.date`
   freshness check.
7. Add `.welcoming` to `OnboardingView.welcomePage`.
8. Add the same empty-state treatment to `InsightsView`, replacing its
   `ContentUnavailableView` — carry over an equivalent accessibility label
   on the container (see Section 4's Insights row).

Notification rich-attachment work (previously step 8 in the original
draft) is cut from this list — see Section 8.3.

## 7. Do's and Don'ts

- **Do** keep the capybara ambient — empty states, streaks, onboarding,
  the widget.
- **Do** let a bad trend or active flare always outrank a celebratory pose.
- **Do** mark every mascot image `.accessibilityHidden(true)` — it's
  decorative by design (Section 1's "no dialogue" rule), and the
  accessibility label lives on the surrounding text/container instead.
- **Don't** put it anywhere near symptom severity, pain, medication
  logging, or the doctor/personal PDF.
- **Don't** give it dialogue, speech bubbles, or first-person copy.
- **Don't** bake color into the artwork, and don't design two-tone
  (outline + fill in different shades) art for Template Image assets —
  tint via `CadenceColor` only, and it flattens to one color.
- **Don't** duplicate `MascotPoseEngine`'s logic per-surface — Dashboard,
  widget, and (when picked back up) notifications must never disagree on
  which pose is "correct" for a given day.
- **Don't** add a new `Flare` fetch to the watch/Siri quick-log paths just
  to feed the mascot — widen `publishWidgetSummary`'s signature (Section
  6, step 5) and accept that those paths publish a flare-blind pose until
  the next full Dashboard refresh, which follows almost immediately in
  practice.

## 8. Review Findings (2026-07-21) and Resolutions

A technical review cross-checked this draft against the actual codebase
before implementation started. Five gaps were found; this section records
each and how it's resolved above, so the reasoning isn't lost.

### 8.1 — `publishWidgetSummary`'s blast radius was understated

The original draft said "the Dashboard computes the pose once ... written
in `DashboardViewModel.publishWidgetSummary(logs:)`," implying a small,
Dashboard-local change. In reality `publishWidgetSummary` is a `static
func` called from **7 sites**: `CadenceApp` (foreground refresh),
`LogInputFlow` (every save), `PhoneConnectivityManager` (watch quick-log),
`CheckInIntents` (Siri quick-log), `SyncBackupSection` (restore), plus
`DashboardViewModel.refresh` itself — and it previously took only
`logs: [DailyLog]`, no Flare data.

**Resolution:** give it a `flares: [Flare] = []` default, matching the
existing default-parameter convention on `DashboardViewModel.refresh`.
`refresh` already receives `flares` as a parameter (wired in for
`PatternEngine`) and can pass it through for free — no new fetch. The
other 6 call sites are narrow, single-purpose save paths; adding a
`FetchDescriptor<Flare>` to each just for the mascot would be
disproportionate for a decorative feature. They publish with the default
`[]`, meaning `.cozy` may lag by one refresh cycle after a quick-log —
consistent with how the widget already tolerates brief staleness elsewhere
(the documented "mood saved" interim state).

### 8.2 — The Dashboard doesn't have a "no log yet today" empty state

The original draft's Section 4 described the Dashboard empty state as
firing "when there's no log yet today" and mapped it to `.resting`. The
actual `DashboardView.emptyState` is gated on `logs.isEmpty` — the
90-day query window being completely empty, i.e. a true first-time or
long-lapsed user. That condition matches `.welcoming`, not `.resting`.
"Has history, but nothing logged today" isn't a distinct empty state on
the Dashboard at all — it's handled inline by `todayCard`'s persistent
"Not started — 90 seconds" text, which shows regardless of history.

**Resolution:** `.resting`'s trigger condition maps cleanly onto the
**widget's** existing `loggedToday == false` boolean instead, and that's
its primary placement for MVP. The Dashboard's empty state uses
`.welcoming`, matching what it actually checks. This is reflected in the
corrected Section 2 table and Section 4/6 above.

**Further refinement (implementation, 2026-07-21):** building
`MascotPoseEngine` surfaced that `.resting` doesn't need `loggedToday`
logic at all — it's simplest and most consistent as the engine's plain
**default**: "has history, and nothing else (`.cozy`/`.soaking`) applies,"
full stop, regardless of whether today specifically is logged. This covers
the same cases (including "no check-in yet") without the engine needing to
know what day it is beyond what's already implicit in `logs`, and it means
the widget's own `loggedToday`-driven copy ("Tap to check in") stays a
completely separate, independent concern from which pose renders — the
mascot and the text next to it can already differ in what they're
responding to (e.g. an active flare shows `.cozy` even on a day that *is*
logged), so decoupling them outright is more correct, not less. `MascotPoseEngine.pose`
(`Cadence/Services/MascotPoseEngine.swift`) implements this; see
`docs/superpowers/plans/2026-07-21-mascot-pose-engine.md` for the full
priority logic and its tests.

### 8.3 — Rich notification attachments need a file URL, not an asset name

`UNNotificationAttachment(identifier:url:options:)` requires an actual
file on disk. Asset Catalog entries compile into `Assets.car` and aren't
directly usable as that URL — nothing in this codebase does that today
(`grep -r UNNotificationAttachment` returns nothing). The Art Production
pipeline (vector → Asset Catalog → Template Image) doesn't produce
anything the notification step can consume as-is.

**Resolution:** deferred out of MVP. The evening daily reminder ships
without a mascot image; `.sleepy` stays defined as a pose (for a possible
future in-app surface) but isn't wired to a notification. If picked up
later, the correct approach is either bundling a loose image file
specifically for this one pose (bypassing the asset catalog for that
asset) or rendering/exporting to a temp file at schedule time — not
reusing `Image("mascot-sleepy")` as-is.

### 8.4 — Streak badge is a tight fit for an inline illustration

`StreakBadge` is a compact single-row `HStack` (flame icon, count, "days"
text) inside the Dashboard's greeting header today. A `.soaking`
capybara-in-a-hot-spring illustration sitting "additive, inline" next to
it is the one placement genuinely competing for space with an existing
tight UI element, rather than filling an empty state.

**Resolution:** not blocking, but flagged as needing a real mock at actual
device size before implementation (Section 4's Streak badge row). If it
doesn't fit cleanly inline, the fallback is a small illustration placed
near/below the badge rather than sharing its `HStack`.

### 8.5 — Template Image rendering is single-tint, not single-region

The original draft's "line work + exactly one fill region" phrasing was
ambiguous about whether the outline and fill could be different shades.
Template Image rendering flattens **every** non-transparent pixel to one
tint color — there's no such thing as a two-tone Template Image asset.

**Resolution:** Section 5's art guidance now states this as a hard
constraint (single-color-total, not just single-fill-region). A two-tone
look, if wanted later, requires two separately-tinted template layers per
pose and is scoped as a v2 exploration, not MVP.
