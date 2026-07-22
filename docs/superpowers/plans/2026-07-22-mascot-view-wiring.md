# Mascot View Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mascot illustrations (already staged in both asset catalogs,
already pose-computed by `MascotPoseEngine`/`WidgetData.Summary.mascotPose`)
actually render, on the 3 surfaces where placement is unambiguous.

**Architecture:** `DashboardViewModel` gains a published `mascotPose`
property, computed the same way `publishWidgetSummary` already computes it
(shared private helper, no duplicated logic). Three view surfaces read a
`MascotPose` value they already have access to (`DashboardViewModel`'s new
property, or `WidgetData.Summary.mascotPose` the widget already receives)
and render `Image("mascot-<pose>")`.

**Tech Stack:** SwiftUI, the `WidgetData.MascotPose`/`MascotPoseEngine`
built on the `feature/mascot-pose-engine` branch (this plan continues on
that same branch — it depends on that work, not on `main`).

## Global Constraints

- Every mascot image is decorative: `.accessibilityHidden(true)` on every
  one, no exceptions — the surrounding text/UI already carries the meaning
  (spec Section 1's "no dialogue" rule, restated as a hard requirement in
  Section 7's Do's).
- Asset names are `mascot-welcoming`, `mascot-resting`, `mascot-soaking`,
  `mascot-cozy`, `mascot-sleepy` — `Image("mascot-\(pose.rawValue)")`,
  already the case names on `WidgetData.MascotPose`.
- **Scope cut from the original spec, decided during this plan's
  research, with reasons — do not re-litigate without new evidence:**
  - **Insights tab empty state is explicitly OUT of scope.**
    `InsightsView.chartsEmptyState` (`Cadence/Features/Insights/InsightsView.swift:151-160`)
    carries the comment "System empty-state component (matches History,
    Flares, Medications…) rather than a hand-rolled card" — `HistoryView`,
    `FlaresView`, and `MedicationsView` all use `ContentUnavailableView` for
    their own empty states too. This is a real, deliberate, four-surface
    consistency decision already in the codebase; swapping only Insights
    for a custom illustration breaks it for no strong reason. Dashboard's
    empty state has no such constraint — it was already a hand-rolled
    `VStack`, never `ContentUnavailableView`.
  - **The streak badge is OUT of scope.** `StreakBadge`
    (`Cadence/Shared/Components/MetricSlider.swift:75-107`) is a compact
    single-row `HStack` (~24–28pt tall including padding). The mascot art
    has fine detail (steam wisps, water rings, facial features) that needs
    roughly 32–44pt+ to read clearly — comparable to the 52pt icon circles
    `DashboardView.todayCard`/`weeklyCard` already use for their glanceable
    icons. Scaled to fit the badge's row height, the illustration would be
    illegible. This needs actual visual design iteration (a real mock, or
    an alternate placement not sharing the badge's `HStack`), not a blind
    implementation — left for a future pass.
- No behavior changes to pose computation — this plan only adds
  `Image(...)` calls and one new `DashboardViewModel` property that reads
  values `MascotPoseEngine`/`publishWidgetSummary` already compute
  correctly (verified by the prior plan's 231-test full-suite run).
- **This environment now has a working simulator destination** — a
  discovery made while finishing the prior plan, after most of that plan's
  own verification had to fall back to `swiftc -parse`/single-target
  builds. Use it for every verification step in this plan:
  `xcodebuild test -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone'`
  for the full suite, and `xcrun simctl` / Xcode Previews for visual
  checks. Do not fall back to `swiftc -parse`-only verification here — a
  real build is available and view code specifically needs to be seen, not
  just parsed.

---

### Task 1: `DashboardViewModel.mascotPose` published property

**Files:**
- Modify: `Cadence/Features/Dashboard/DashboardViewModel.swift`

**Interfaces:**
- Consumes: `MascotPoseEngine.pose(for:activeFlare:streakDays:)`,
  `WidgetData.MascotPose` (both already exist on this branch).
- Produces: `DashboardViewModel.mascotPose: WidgetData.MascotPose`
  (published `@Observable` property, set by `refresh(...)`) — consumed by
  Task 3 (Dashboard empty state).

- [ ] **Step 1: Extract the shared pose-resolution helper and add the property**

Open `Cadence/Features/Dashboard/DashboardViewModel.swift`. Find this exact
block:

```swift
@MainActor
@Observable
final class DashboardViewModel {
    var todayLog: DailyLog?
    var thisWeekReview: WeeklyReview?
    var streak: Int = 0
    var latestInsight: InsightCard?

    func refresh(logs: [DailyLog], reviews: [WeeklyReview], medications: [Medication] = [], flares: [Flare] = [], customTrackers: [CustomTracker] = [], notifications: (any NotificationServiceProtocol)? = nil) {
        let notifications = notifications ?? NotificationService.shared
        todayLog = logs.first { Calendar.current.isDateInToday($0.date) }
        thisWeekReview = reviews.first { $0.weekStartDate.isThisWeek }
        streak = Self.computeStreak(from: logs)
        // Snapshot @Model values on the main actor before handing them to
        // PatternEngine. Every input PatternEngine takes is included so the
        // dashboard headline agrees with the Insights tab / notifications
        // about the top pattern (all three run off the same input set).
        latestInsight = PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init),
            flares: flares.map(FlareSnapshot.init),
            trackers: customTrackers.map(CustomTrackerSnapshot.init)
        ).first

        if streak > 0 && todayLog?.isComplete != true {
            notifications.scheduleStreakAtRisk()
        } else {
            notifications.removeNotification(id: NotificationID.streakRisk)
        }

        Self.publishWidgetSummary(logs: logs, flares: flares)
    }

    // Single publish point for the home-screen widget, callable from any save
    // path (dashboard refresh, watch quick-log, log flow). Skips the write AND
    // the timeline reload when nothing changed — reloads are system-budgeted,
    // and burning the budget on no-op refreshes leaves real changes stranded.
    //
    // `flares` defaults to `[]` only for callers with no ModelContext in
    // scope at all (none currently exist — every real call site fetches
    // Flare alongside DailyLog, the same cheap unbounded-table fetch already
    // used for Medication elsewhere). This isn't optional: a caller that
    // publishes without flares would silently overwrite an active flare's
    // stored `.cozy` pose with whatever `.soaking`/`.resting`/`.welcoming`
    // the flare-blind computation produces instead — not a staleness lag,
    // an active downgrade, since `pose` is recomputed from scratch each call
    // and the `summary != WidgetData.read()` guard republishes any different
    // value it gets.
    static func publishWidgetSummary(logs: [DailyLog], flares: [Flare] = []) {
        let streak = computeStreak(from: logs)
        let activeFlare = flares.first { $0.endDate == nil }
        let summary = WidgetData.Summary(
            date: Calendar.current.startOfDay(for: .now),
            loggedToday: logs.first { Calendar.current.isDateInToday($0.date) }?.isComplete == true,
            streak: streak,
            mascotPose: MascotPoseEngine.pose(
                for: logs.map(DailyLogSnapshot.init),
                activeFlare: activeFlare.map(FlareSnapshot.init),
                streakDays: streak
            )
        )
        guard summary != WidgetData.read() else { return }
        WidgetData.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
```

Replace it with (adds `mascotPose` to the property list, sets it in
`refresh`, and extracts `resolvePose` so `refresh` and
`publishWidgetSummary` compute it identically instead of duplicating the
active-flare-selection line):

```swift
@MainActor
@Observable
final class DashboardViewModel {
    var todayLog: DailyLog?
    var thisWeekReview: WeeklyReview?
    var streak: Int = 0
    var latestInsight: InsightCard?
    var mascotPose: WidgetData.MascotPose = .welcoming

    func refresh(logs: [DailyLog], reviews: [WeeklyReview], medications: [Medication] = [], flares: [Flare] = [], customTrackers: [CustomTracker] = [], notifications: (any NotificationServiceProtocol)? = nil) {
        let notifications = notifications ?? NotificationService.shared
        todayLog = logs.first { Calendar.current.isDateInToday($0.date) }
        thisWeekReview = reviews.first { $0.weekStartDate.isThisWeek }
        streak = Self.computeStreak(from: logs)
        // Snapshot @Model values on the main actor before handing them to
        // PatternEngine. Every input PatternEngine takes is included so the
        // dashboard headline agrees with the Insights tab / notifications
        // about the top pattern (all three run off the same input set).
        latestInsight = PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init),
            flares: flares.map(FlareSnapshot.init),
            trackers: customTrackers.map(CustomTrackerSnapshot.init)
        ).first
        mascotPose = Self.resolvePose(logs: logs, flares: flares, streakDays: streak)

        if streak > 0 && todayLog?.isComplete != true {
            notifications.scheduleStreakAtRisk()
        } else {
            notifications.removeNotification(id: NotificationID.streakRisk)
        }

        Self.publishWidgetSummary(logs: logs, flares: flares)
    }

    // Shared by refresh (for the Dashboard's own mascotPose) and
    // publishWidgetSummary (for the widget's copy) so the two can never
    // disagree about which flare counts as "active" or how streak feeds
    // into the pose.
    private static func resolvePose(logs: [DailyLog], flares: [Flare], streakDays: Int) -> WidgetData.MascotPose {
        let activeFlare = flares.first { $0.endDate == nil }
        return MascotPoseEngine.pose(
            for: logs.map(DailyLogSnapshot.init),
            activeFlare: activeFlare.map(FlareSnapshot.init),
            streakDays: streakDays
        )
    }

    // Single publish point for the home-screen widget, callable from any save
    // path (dashboard refresh, watch quick-log, log flow). Skips the write AND
    // the timeline reload when nothing changed — reloads are system-budgeted,
    // and burning the budget on no-op refreshes leaves real changes stranded.
    //
    // `flares` defaults to `[]` only for callers with no ModelContext in
    // scope at all (none currently exist — every real call site fetches
    // Flare alongside DailyLog, the same cheap unbounded-table fetch already
    // used for Medication elsewhere). This isn't optional: a caller that
    // publishes without flares would silently overwrite an active flare's
    // stored `.cozy` pose with whatever `.soaking`/`.resting`/`.welcoming`
    // the flare-blind computation produces instead — not a staleness lag,
    // an active downgrade, since `pose` is recomputed from scratch each call
    // and the `summary != WidgetData.read()` guard republishes any different
    // value it gets.
    static func publishWidgetSummary(logs: [DailyLog], flares: [Flare] = []) {
        let streak = computeStreak(from: logs)
        let summary = WidgetData.Summary(
            date: Calendar.current.startOfDay(for: .now),
            loggedToday: logs.first { Calendar.current.isDateInToday($0.date) }?.isComplete == true,
            streak: streak,
            mascotPose: resolvePose(logs: logs, flares: flares, streakDays: streak)
        )
        guard summary != WidgetData.read() else { return }
        WidgetData.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
```

- [ ] **Step 2: Build and run the full suite**

```bash
xcodebuild test -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone' 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`, `Test run with 231 tests in 56 suites
passed` (same count as before — this step adds no new tests, since
`resolvePose`/`mascotPose` are exercised indirectly through
`MascotPoseEngine`'s existing 10 tests and `refresh`/`publishWidgetSummary`
have no direct unit tests today, matching this codebase's existing
coverage boundary for that ViewModel).

- [ ] **Step 3: Commit**

```bash
git add Cadence/Features/Dashboard/DashboardViewModel.swift
git commit -m "Add DashboardViewModel.mascotPose, shared with publishWidgetSummary's pose resolution"
```

---

### Task 2: Onboarding welcome page mascot

**Files:**
- Modify: `Cadence/Features/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `WidgetData.MascotPose` (no dependency on Task 1 — this is a
  static `.welcoming`, not view-model-driven).
- Produces: nothing consumed by later tasks — independent of Task 1/3/4.

- [ ] **Step 1: Add an optional mascot to `OnboardingPage`, used only by the welcome page**

Open `Cadence/Features/Onboarding/OnboardingView.swift`. Find this exact
block:

```swift
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var isBusy: Bool = false
    let primaryLabel: String
    let primaryAction: () -> Void
    var skipAction: (() -> Void)? = nil

    @State private var iconAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: iconAppeared)
                    .onAppear { iconAppeared = true }
```

Replace it with (adds an optional `mascotPose`; when set, it renders
instead of the SF Symbol for that one page — showing both a large SF
Symbol and a large illustration together would compete for attention on a
first-impression screen, so this is a replacement, not an addition, for
whichever page opts in):

```swift
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var isBusy: Bool = false
    let primaryLabel: String
    let primaryAction: () -> Void
    var skipAction: (() -> Void)? = nil
    // Set only by the welcome page. Replaces the SF Symbol rather than
    // sitting alongside it — decorative, so it's accessibilityHidden; the
    // title/message text below already carries the page's meaning.
    var mascotPose: WidgetData.MascotPose? = nil

    @State private var iconAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                if let mascotPose {
                    Image("mascot-\(mascotPose.rawValue)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(iconColor)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 80))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: iconAppeared)
                        .onAppear { iconAppeared = true }
                }
```

Note: `.foregroundStyle(iconColor)` on the mascot `Image` only has a visible
effect if the `mascot-welcoming` image set's "Render As" is Template Image
(per the art pipeline in `docs/superpowers/specs/2026-07-21-mascot-design.md`
Section 5) — confirm this visually in Step 3; if the mascot renders in a
fixed color regardless of `iconColor`, the asset isn't set to template
rendering and that's an asset-catalog fix, not a code fix.

- [ ] **Step 2: Pass `.welcoming` from the welcome page only**

Find this exact block:

```swift
    private var welcomePage: some View {
        OnboardingPage(
            icon: "waveform.path.ecg.rectangle.fill",
            iconColor: CadenceColor.accent,
            title: "Welcome to Cadence",
            message: "Track how you feel, sleep, and move — in under two minutes a day. Over time, Cadence finds patterns you wouldn't notice on your own.",
            primaryLabel: "Get Started",
            primaryAction: advance
        )
    }
```

Replace it with:

```swift
    private var welcomePage: some View {
        OnboardingPage(
            icon: "waveform.path.ecg.rectangle.fill",
            iconColor: CadenceColor.accent,
            title: "Welcome to Cadence",
            message: "Track how you feel, sleep, and move — in under two minutes a day. Over time, Cadence finds patterns you wouldn't notice on your own.",
            primaryLabel: "Get Started",
            primaryAction: advance,
            mascotPose: .welcoming
        )
    }
```

The other three pages (`notificationsPage`, `healthKitPage`, `readyPage`)
are unchanged — they don't pass `mascotPose`, so they keep using their SF
Symbol via the `else` branch added in Step 1.

- [ ] **Step 3: Build and visually verify**

```bash
xcodebuild build -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

Then actually look at it — launch the app in the simulator with a fresh
onboarding state and screenshot the welcome page:

```bash
xcrun simctl boot "Cadence Test iPhone" 2>/dev/null || true
xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone' -derivedDataPath /tmp/cadence-build install 2>&1 | tail -5
xcrun simctl install "Cadence Test iPhone" /tmp/cadence-build/Build/Products/Debug-iphonesimulator/Cadence.app
xcrun simctl launch "Cadence Test iPhone" com.carpecadence.app --args --uitest
sleep 2
xcrun simctl io "Cadence Test iPhone" screenshot /tmp/onboarding-welcome.png
```

Read `/tmp/onboarding-welcome.png` (via the Read tool) and confirm: the
mascot renders (not a broken-image placeholder — if the asset name doesn't
resolve, SwiftUI's `Image(_:)` renders nothing, an empty space, not a
visible error, so absence is the failure signature to watch for), it's
legible at 120×120, it's tinted `CadenceColor.accent` if the asset is
template-rendered (per the Step 1 note), and the page still reads as a
coherent welcome screen (title/message/button not crowded out).

If the mascot doesn't render at all: check the asset actually exists at
this path (`Cadence/Assets.xcassets/mascot-welcoming.imageset/`) and that
its `Contents.json` `filename` matches exactly. If it renders but looks
wrong (too small/large, wrong color), adjust the `frame`/`foregroundStyle`
in Step 1 and re-screenshot — this is exactly the kind of thing that needs
seeing, not guessing.

- [ ] **Step 4: Commit**

```bash
git add Cadence/Features/Onboarding/OnboardingView.swift
git commit -m "Show the welcoming mascot on the onboarding welcome page"
```

---

### Task 3: Dashboard empty state mascot

**Files:**
- Modify: `Cadence/Features/Dashboard/DashboardView.swift`

**Interfaces:**
- Consumes: `DashboardViewModel.mascotPose` (Task 1).

- [ ] **Step 1: Add the mascot to `emptyState`**

Open `Cadence/Features/Dashboard/DashboardView.swift`. Find this exact
block:

```swift
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Log your first day to see insights")
                .font(.subheadline.weight(.medium))
            Text("Tap Today's Log above to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cadenceCard()
    }
```

Replace it with:

```swift
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("mascot-\(vm.mascotPose.rawValue)")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Log your first day to see insights")
                .font(.subheadline.weight(.medium))
            Text("Tap Today's Log above to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cadenceCard()
    }
```

`vm.mascotPose` will be `.welcoming` whenever this specific view is
visible in practice (`emptyState` only renders when `logs.isEmpty`, which
is exactly `MascotPoseEngine.pose`'s own `.welcoming` condition — see
`docs/superpowers/specs/2026-07-21-mascot-design.md` Section 8.2) but
reading the live property rather than hardcoding `.welcoming` here keeps
this view correct automatically if that invariant ever changes, with no
special-casing.

- [ ] **Step 2: Build and visually verify**

```bash
xcodebuild build -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

Screenshot the Dashboard tab in its empty state (a fresh `--uitest` launch
has no logs yet, so this state should show immediately without extra
setup):

```bash
xcrun simctl launch "Cadence Test iPhone" com.carpecadence.app --args --uitest
sleep 2
xcrun simctl io "Cadence Test iPhone" screenshot /tmp/dashboard-empty.png
```

Read `/tmp/dashboard-empty.png` and confirm the mascot renders at a
reasonable size relative to the rest of the card, doesn't crowd the two
text lines, and the overall Dashboard (greeting header, streak badge if
present, today/weekly cards above it) still looks balanced with this card
now taller than before.

- [ ] **Step 3: Commit**

```bash
git add Cadence/Features/Dashboard/DashboardView.swift
git commit -m "Show the mascot in the Dashboard's empty state"
```

---

### Task 4: Home Screen widget mascot

**Files:**
- Modify: `CadenceWidget/CadenceWidget.swift`

**Interfaces:**
- Consumes: `WidgetData.Summary.mascotPose` (already on `entry.summary`,
  already flowing through every `#Preview` block from the prior plan).

- [ ] **Step 1: Add the mascot to `systemView` (Home Screen `.systemSmall`/`.systemMedium` only)**

Open `CadenceWidget/CadenceWidget.swift`. Find this exact block:

```swift
    private var systemView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(entry.summary.streak)")
                    .font(.system(.title, design: .rounded).bold())
                    .contentTransition(.numericText())
                Text(entry.summary.streak == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // iOS 18 tinted Home Screens flatten colors; keep the streak
            // cluster legible as the accented element.
            .widgetAccentable()

            if family != .systemSmall {
                Text("logging streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.summary.loggedToday {
                Label("Logged today", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else if let mood = entry.pendingMood {
                // A tap was recorded but the app hasn't opened to persist it —
                // "saved", not "logged", stays truthful about the difference.
                Label("\(MoodScale.emoji(for: mood)) Mood saved", systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                moodButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
```

Replace it with (mascot as a bottom-trailing background accent behind the
existing content, not competing with the streak number or the functional
mood buttons/status row — a corner illustration under everything else,
matching the "ambient, not the main event" design principle from the
spec's Section 1):

```swift
    private var systemView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(entry.summary.streak)")
                    .font(.system(.title, design: .rounded).bold())
                    .contentTransition(.numericText())
                Text(entry.summary.streak == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // iOS 18 tinted Home Screens flatten colors; keep the streak
            // cluster legible as the accented element.
            .widgetAccentable()

            if family != .systemSmall {
                Text("logging streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.summary.loggedToday {
                Label("Logged today", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else if let mood = entry.pendingMood {
                // A tap was recorded but the app hasn't opened to persist it —
                // "saved", not "logged", stays truthful about the difference.
                Label("\(MoodScale.emoji(for: mood)) Mood saved", systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                moodButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image("mascot-\(entry.summary.mascotPose.rawValue)")
                .resizable()
                .scaledToFit()
                .frame(width: family == .systemSmall ? 44 : 56, height: family == .systemSmall ? 44 : 56)
                .opacity(0.5)
                .accessibilityHidden(true)
                .padding(.trailing, -4)
                .padding(.bottom, -4)
        }
    }
```

- [ ] **Step 2: Build and visually verify via widget preview**

```bash
xcodebuild build -scheme Cadence -destination 'platform=iOS Simulator,name=Cadence Test iPhone' 2>&1 | tail -20
xcodebuild build -project Cadence.xcodeproj -target CadenceWidgetExtension -destination 'platform=iOS Simulator,name=Cadence Test iPhone' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **` for both.

Open `CadenceWidget/CadenceWidget.swift` in Xcode and use the `#Preview(as:
.systemSmall)` canvas (already has both a `.welcoming` and a `.resting`
timeline entry from the prior plan) to see the mascot rendered against
real widget content — this is faster and more reliable for widget-specific
layout than a simulator screenshot, since widgets don't reliably appear on
a fresh simulator's Home Screen without manually adding them.

If Xcode Previews aren't drivable in this environment, fall back to: add a
temporary `#Preview` with a `.cozy`/`.soaking` entry too, build the
`CadenceWidgetExtension` target, and report BUILD SUCCEEDED plus a written
description of the layout math (opacity, corner position, size vs. the
44×44/56×56 frame) as the closest available verification — note clearly in
the report if visual confirmation wasn't actually possible, don't claim it
happened if it didn't.

Confirm across all 5 poses (swap `mascotPose:` in the preview timelines
temporarily to check each one renders, then revert): the mascot doesn't
overlap or obscure the streak number, the mood-button row, or the "logged
today"/"mood saved" text; it reads as a subtle corner accent, not the
focal point; `.systemSmall`'s tighter width doesn't clip it.

- [ ] **Step 3: Commit**

```bash
git add "CadenceWidget/CadenceWidget.swift"
git commit -m "Show the mascot as a corner accent on the Home Screen widget"
```

---

## What's still not in this plan

- **Streak badge** — deferred, needs real visual design iteration at a
  size the art can actually read at (see Global Constraints).
- **Insights tab empty state** — deliberately excluded to preserve its
  documented consistency with History/Flares/Medications' shared
  `ContentUnavailableView` pattern (see Global Constraints).
- **Notification rich attachment (`.sleepy`)** — still needs its own
  file-URL-based approach; unrelated to any view code, spec Section 8.3.
- **Lock Screen / StandBy accessory families** — spec explicitly keeps
  these symbol-only (too small for the art to read); `circularView`,
  `rectangularView`, `inlineView` are untouched by this plan.
