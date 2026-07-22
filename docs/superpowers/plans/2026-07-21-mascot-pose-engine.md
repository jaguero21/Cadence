# Mascot Pose Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and fully unit-test the mascot's pose-resolution logic and its
data plumbing to the widget — everything in the design spec that doesn't
require the actual mascot artwork to exist.

**Architecture:** A pure `MascotPoseEngine.pose(for:activeFlare:streakDays:)`
function (snapshot-based, no `@Model` crossing actor boundaries) resolves one
of 5 `MascotPose` cases by the same "strongest signal wins" priority
`PatternEngine` already uses. The app computes it and publishes it as a new
field on `WidgetData.Summary` so the widget extension — which has no
SwiftData access — can read the same pose without recomputing it.

**Tech Stack:** Swift, SwiftData snapshots, Swift Testing (`@Suite`/`@Test`/`#expect`).

## Global Constraints

- Reference spec: `docs/superpowers/specs/2026-07-21-mascot-design.md` (read
  Sections 1–3 and 8 before starting — Section 8 records why this plan's
  file placements differ from the spec's original suggestions).
- Pose priority, highest first: `.cozy` > `.soaking` > `.resting` >
  `.welcoming`. `.sleepy` is defined but has no trigger logic in this plan
  (notification wiring is deferred — spec Section 8.3).
- `MascotThreshold.streakDaysForSoaking = 7`, `MascotThreshold.lowMoodTrendDays = 3`.
- `MascotPose` must be `String, CaseIterable, Codable` and must live in
  `CadenceWidget/WidgetData.swift`, **not** `Cadence/Models/` — that file is
  the only one already compiled into both the `Cadence` and
  `CadenceWidgetExtension` targets, and `WidgetData.Summary` (which needs
  this type) must compile in both. Defining it anywhere app-target-only
  would break the widget extension's build.
- `MascotPoseEngine` takes `FlareSnapshot?`, never `Flare?` — no `@Model`
  crosses an actor boundary, matching the rule already documented for
  `PatternEngine`.
- No force unwraps, `try!`, `fatalError`, or `assert` in
  `MascotPoseEngine.swift` itself (a shipped code path) — guard/optional
  chaining only, matching this codebase's hard rule. Task 3's test file is
  the one exception: its `makeLog` helper force-unwraps a
  `Calendar.date(byAdding:...)` call, mirroring the exact pattern
  `PatternEngineTests.swift`'s own `makeSnapshot` helper already uses —
  test helper code isn't a shipped path, and this matches established
  precedent rather than violating it.
- **This plan does not add `Image("mascot-<pose>")` calls anywhere.** No
  view code changes. The mascot artwork doesn't exist yet (vector art is in
  progress separately); wiring images to views that reference non-existent
  assets isn't independently testable and is out of scope here. That work
  is a follow-up plan once assets land in `Assets.xcassets`.
- **Environment note for whoever runs this plan:** a full `Cadence` app
  target build (needed to run `CadenceTests`, since it's hosted inside
  `Cadence.app`) may be blocked in some environments by an unrelated
  watchOS-simulator-runtime mismatch that has nothing to do with this
  code (confirmed earlier by building `CadenceWidgetExtension` alone
  successfully, while the full `Cadence` scheme failed on the embedded
  watch app's asset-catalog step). If `xcodebuild test -scheme Cadence`
  won't run in your environment, verify Task 3's tests by opening the
  project in Xcode and running ⌘U instead.

---

### Task 1: `MascotThreshold` constants

**Files:**
- Modify: `Cadence/Shared/Constants.swift`

**Interfaces:**
- Produces: `MascotThreshold.streakDaysForSoaking: Int`,
  `MascotThreshold.lowMoodTrendDays: Int` — consumed by Task 3's
  `MascotPoseEngine`.

- [ ] **Step 1: Add the `MascotThreshold` enum**

Open `Cadence/Shared/Constants.swift`. Find this exact block (the end of
`HealthThreshold`, right before `AppLaunch`):

```swift
enum HealthThreshold {
    // A day's HealthKit workouts count as "Intense exercise" (auto-selecting
    // that factor chip) when they total at least this much time or energy.
    static let intenseWorkoutMinutes: Double = 45
    static let intenseWorkoutKilocalories: Double = 400
    // Logged dietary caffeine (mg) that auto-selects the "Caffeine" factor —
    // roughly half a cup of coffee; trace amounts don't count.
    static let caffeineMilligrams: Double = 50
    // Logged dietary water (litres) that auto-checks the "Hydration" basic.
    static let hydrationLiters: Double = 1.5
}

enum AppLaunch {
```

Replace it with (adds the new enum between `HealthThreshold` and
`AppLaunch`, changing nothing else):

```swift
enum HealthThreshold {
    // A day's HealthKit workouts count as "Intense exercise" (auto-selecting
    // that factor chip) when they total at least this much time or energy.
    static let intenseWorkoutMinutes: Double = 45
    static let intenseWorkoutKilocalories: Double = 400
    // Logged dietary caffeine (mg) that auto-selects the "Caffeine" factor —
    // roughly half a cup of coffee; trace amounts don't count.
    static let caffeineMilligrams: Double = 50
    // Logged dietary water (litres) that auto-checks the "Hydration" basic.
    static let hydrationLiters: Double = 1.5
}

enum MascotThreshold {
    // Consecutive-day streak (see DashboardViewModel.computeStreak) at or
    // above which the mascot switches to its ".soaking" (hot-spring) pose.
    static let streakDaysForSoaking: Int = 7
    // How many of the most recently logged days (by date, gaps allowed —
    // see MascotPoseEngine.hasLowMoodTrend) must all sit below the overall
    // average mood before the mascot switches to its ".cozy" pose. 3 is
    // long enough that a single off day can't flip it.
    static let lowMoodTrendDays: Int = 3
}

enum AppLaunch {
```

- [ ] **Step 2: Syntax-check the file**

Run: `xcrun swift-format lint Cadence/Shared/Constants.swift 2>&1 || true`

(This project has no swift-format/lint tooling configured — this command is
just a syntax sanity check and is expected to either no-op or print a "tool
not found" message, not a real gate. The real check is Task 3's build.)

- [ ] **Step 3: Commit**

```bash
git add Cadence/Shared/Constants.swift
git commit -m "Add MascotThreshold constants for the mascot pose engine"
```

---

### Task 2: `MascotPose` enum and `WidgetData.Summary` field

**Files:**
- Modify: `CadenceWidget/WidgetData.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `MascotPose: String, CaseIterable, Codable` enum with cases
  `.welcoming, .resting, .soaking, .cozy, .sleepy`; `WidgetData.Summary`
  gains a non-optional `mascotPose: MascotPose` field. Both consumed by
  Task 3 (return type) and Task 4 (field assignment).

- [ ] **Step 1: Add `MascotPose` and widen `Summary`**

Open `CadenceWidget/WidgetData.swift`. Find this exact block:

```swift
    struct Summary: Codable, Equatable {
        var date: Date          // start of day the summary describes
        var loggedToday: Bool
        var streak: Int
    }
```

Replace it with:

```swift
    // Ambient companion pose, computed by MascotPoseEngine
    // (Cadence/Services/MascotPoseEngine.swift) on the app side and
    // published here so the widget extension — which has no SwiftData
    // access — can render the same pose without recomputing it. Defined
    // here rather than in Cadence/Models/ because this file is already
    // compiled into both the Cadence and CadenceWidgetExtension targets,
    // and Summary (below) needs this type to compile in both.
    enum MascotPose: String, CaseIterable, Codable {
        case welcoming, resting, soaking, cozy, sleepy
    }

    struct Summary: Codable, Equatable {
        var date: Date          // start of day the summary describes
        var loggedToday: Bool
        var streak: Int
        var mascotPose: MascotPose
    }
```

Note: this makes `Summary` gain a required field. A `Summary` value
persisted by a previous build of the app (before this change) will fail to
decode once — `WidgetData.read()` already wraps the decode in `try?` and
callers already treat a decode failure as "no stored summary" (see
`WidgetData.resolved(_:now:)`), so this self-heals on the next
`publishWidgetSummary` call rather than crashing. No code change needed for
this; noting it so it isn't mistaken for a bug later.

- [ ] **Step 2: Build the widget extension target to confirm this compiles**

Run: `xcodebuild -project Cadence.xcodeproj -target CadenceWidgetExtension -destination 'generic/platform=iOS' build 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`. If it fails, the error will be a real
compile error in `WidgetData.swift` (this target has no other dependency on
unrelated code) — fix before continuing.

- [ ] **Step 3: Clean up build artifacts**

```bash
rm -rf build
```

- [ ] **Step 4: Commit**

```bash
git add "CadenceWidget/WidgetData.swift"
git commit -m "Add MascotPose enum and widen WidgetData.Summary with mascotPose"
```

---

### Task 3: `MascotPoseEngine` and its tests

**Files:**
- Create: `Cadence/Services/MascotPoseEngine.swift`
- Create: `CadenceTests/MascotPoseEngineTests.swift`
- Modify: `Cadence.xcodeproj/project.pbxproj` (register both new files —
  see Step 1 and Step 3 below; this project uses explicit file references,
  not synchronized groups, so a new `.swift` file is invisible to the build
  until added here)

**Interfaces:**
- Consumes: `MascotThreshold.streakDaysForSoaking`, `MascotThreshold.lowMoodTrendDays`
  (Task 1); `WidgetData.MascotPose` (Task 2); existing `DailyLogSnapshot`
  (`Cadence/Models/DailyLog.swift`, fields `date: Date`, `mood: Int`) and
  `FlareSnapshot` (`Cadence/Models/Flare.swift`, fields `startDate: Date`,
  `endDate: Date?`).
- Produces: `MascotPoseEngine.pose(for logs: [DailyLogSnapshot], activeFlare: FlareSnapshot?, streakDays: Int) -> WidgetData.MascotPose`
  — consumed by Task 4.

- [ ] **Step 1: Register both new files in the Xcode project**

Open `Cadence.xcodeproj/project.pbxproj` as a text file (not through Xcode's
UI) and make these 8 additions. Each uses an exact existing line as an
anchor — find that exact line and add the new line immediately after it.
Do not reuse or modify any existing UUID; the ones below
(`AABBCCDD0000000000000301` through `...304`) are freshly generated and
don't collide with anything already in the file.

1. In the `PBXBuildFile` section, find:
   ```
   		D34167FEC6764BB077D2EC46 /* PatternEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = 3F0989CA66FE09F78B729A4E /* PatternEngine.swift */; };
   ```
   Add immediately after it:
   ```
   		AABBCCDD0000000000000301 /* MascotPoseEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCCDD0000000000000302 /* MascotPoseEngine.swift */; };
   ```

2. Still in `PBXBuildFile`, find:
   ```
   		AA11BB22CC33DD44EE55FF61 /* PatternEngineTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA11BB22CC33DD44EE55FF01 /* PatternEngineTests.swift */; };
   ```
   Add immediately after it:
   ```
   		AABBCCDD0000000000000303 /* MascotPoseEngineTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCCDD0000000000000304 /* MascotPoseEngineTests.swift */; };
   ```

3. In the `PBXFileReference` section, find:
   ```
   		3F0989CA66FE09F78B729A4E /* PatternEngine.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = PatternEngine.swift; path = ./Cadence/Services/PatternEngine.swift; sourceTree = "<absolute>"; };
   ```
   Add immediately after it:
   ```
   		AABBCCDD0000000000000302 /* MascotPoseEngine.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = MascotPoseEngine.swift; path = ./Cadence/Services/MascotPoseEngine.swift; sourceTree = "<absolute>"; };
   ```

4. Still in `PBXFileReference`, find:
   ```
   		AA11BB22CC33DD44EE55FF01 /* PatternEngineTests.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = PatternEngineTests.swift; path = ./CadenceTests/PatternEngineTests.swift; sourceTree = "<absolute>"; };
   ```
   Add immediately after it:
   ```
   		AABBCCDD0000000000000304 /* MascotPoseEngineTests.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = MascotPoseEngineTests.swift; path = ./CadenceTests/MascotPoseEngineTests.swift; sourceTree = "<absolute>"; };
   ```

5. In the `Services` `PBXGroup`'s `children` array, find:
   ```
   				3F0989CA66FE09F78B729A4E /* PatternEngine.swift */,
   ```
   Add immediately after it:
   ```
   				AABBCCDD0000000000000302 /* MascotPoseEngine.swift */,
   ```

6. In the `CadenceTests` `PBXGroup`'s `children` array, find:
   ```
   				AA11BB22CC33DD44EE55FF01 /* PatternEngineTests.swift */,
   ```
   Add immediately after it:
   ```
   				AABBCCDD0000000000000304 /* MascotPoseEngineTests.swift */,
   ```

7. In the `Cadence` target's `PBXSourcesBuildPhase` (its `files` array),
   find:
   ```
   				D34167FEC6764BB077D2EC46 /* PatternEngine.swift in Sources */,
   ```
   Add immediately after it:
   ```
   				AABBCCDD0000000000000301 /* MascotPoseEngine.swift in Sources */,
   ```

8. In the `CadenceTests` target's `PBXSourcesBuildPhase` (its `files`
   array), find:
   ```
   				AA11BB22CC33DD44EE55FF61 /* PatternEngineTests.swift in Sources */,
   ```
   Add immediately after it:
   ```
   				AABBCCDD0000000000000303 /* MascotPoseEngineTests.swift in Sources */,
   ```

- [ ] **Step 2: Write the failing test file**

Create `CadenceTests/MascotPoseEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import Cadence

// Local helper — PatternEngineTests.swift's makeSnapshot is `private` to
// that file and can't be reused across files.
private func makeLog(daysAgo: Int, mood: Int = 3) -> DailyLogSnapshot {
    DailyLogSnapshot(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, mood: mood)
}

@Suite("MascotPoseEngine – pose")
struct MascotPoseEngineTests {

    @Test("No logs at all returns welcoming")
    func pose_noLogs_isWelcoming() {
        let pose = MascotPoseEngine.pose(for: [], activeFlare: nil, streakDays: 0)
        #expect(pose == .welcoming)
    }

    @Test("Has history, nothing else triggered, returns resting")
    func pose_hasHistory_defaultsToResting() {
        let logs = [makeLog(daysAgo: 0), makeLog(daysAgo: 1)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 2)
        #expect(pose == .resting)
    }

    @Test("Streak at or above the soaking threshold returns soaking")
    func pose_streakAtThreshold_isSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: MascotThreshold.streakDaysForSoaking)
        #expect(pose == .soaking)
    }

    @Test("Streak just below the soaking threshold does not trigger soaking")
    func pose_streakBelowThreshold_isNotSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: MascotThreshold.streakDaysForSoaking - 1)
        #expect(pose != .soaking)
    }

    @Test("An active flare returns cozy even with a qualifying streak")
    func pose_activeFlare_isCozy_outranksSoaking() {
        let logs = [makeLog(daysAgo: 0)]
        let flare = FlareSnapshot(startDate: Date(), endDate: nil)
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: flare, streakDays: 30)
        #expect(pose == .cozy)
    }

    @Test("An ended flare does not trigger cozy")
    func pose_endedFlare_doesNotTriggerCozy() {
        let logs = [makeLog(daysAgo: 0)]
        let flare = FlareSnapshot(startDate: Date(), endDate: Date())
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: flare, streakDays: 0)
        #expect(pose != .cozy)
    }

    @Test("Three consecutive days below the overall average mood returns cozy")
    func pose_lowMoodTrend_isCozy() {
        // Two good days establish a higher average, then three low days in a row.
        let logs = [
            makeLog(daysAgo: 4, mood: 5),
            makeLog(daysAgo: 3, mood: 5),
            makeLog(daysAgo: 2, mood: 1),
            makeLog(daysAgo: 1, mood: 1),
            makeLog(daysAgo: 0, mood: 1),
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose == .cozy)
    }

    @Test("Fewer than lowMoodTrendDays logs never trigger the mood-trend cozy path")
    func pose_tooFewLogs_doesNotTriggerMoodTrend() {
        let logs = [makeLog(daysAgo: 1, mood: 1), makeLog(daysAgo: 0, mood: 1)]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }

    @Test("A single low day among otherwise-average days does not trigger cozy")
    func pose_singleLowDay_doesNotTriggerMoodTrend() {
        let logs = [
            makeLog(daysAgo: 2, mood: 3),
            makeLog(daysAgo: 1, mood: 3),
            makeLog(daysAgo: 0, mood: 1),
        ]
        let pose = MascotPoseEngine.pose(for: logs, activeFlare: nil, streakDays: 0)
        #expect(pose != .cozy)
    }
}
```

- [ ] **Step 3: Confirm the test file is registered**

Run: `grep -c "MascotPoseEngineTests.swift" Cadence.xcodeproj/project.pbxproj`
Expected: `4` (one PBXBuildFile, one PBXFileReference, one group entry, one
Sources phase entry — matches Step 1's additions 2, 4, 6, 8).

- [ ] **Step 4: Write `MascotPoseEngine.swift`**

Create `Cadence/Services/MascotPoseEngine.swift`:

```swift
import Foundation

// Resolves which mascot pose best matches the current moment, using the
// same "strongest signal wins" philosophy as PatternEngine (see
// PatternEngine.allInsights): an active flare or a real low-mood stretch
// always outranks a celebratory streak pose, which outranks the plain
// default. Pure and snapshot-based (never a @Model across actors, same
// rule PatternEngine follows) so every caller — the app now, the widget
// once it's wired — computes the identical pose from the identical inputs.
enum MascotPoseEngine {
    static func pose(
        for logs: [DailyLogSnapshot],
        activeFlare: FlareSnapshot?,
        streakDays: Int
    ) -> WidgetData.MascotPose {
        let isFlareActive = activeFlare.map { $0.endDate == nil } ?? false
        if isFlareActive || hasLowMoodTrend(logs) {
            return .cozy
        }
        if streakDays >= MascotThreshold.streakDaysForSoaking {
            return .soaking
        }
        guard !logs.isEmpty else {
            return .welcoming
        }
        return .resting
    }

    // The most recent `lowMoodTrendDays` logged days (by date, regardless
    // of gaps between them — a user who skipped a day mid-slump should
    // still get the comforting pose) are all below the average mood across
    // every provided log. Requires at least that many logs to evaluate at
    // all, so a single low day early on can't trigger it.
    private static func hasLowMoodTrend(_ logs: [DailyLogSnapshot]) -> Bool {
        guard logs.count >= MascotThreshold.lowMoodTrendDays else { return false }
        let overallMeanMood = Double(logs.map(\.mood).reduce(0, +)) / Double(logs.count)
        let recent = logs.sorted { $0.date > $1.date }.prefix(MascotThreshold.lowMoodTrendDays)
        return recent.allSatisfy { Double($0.mood) < overallMeanMood }
    }
}
```

- [ ] **Step 5: Run the tests**

In Xcode: select the `Cadence` scheme, then Product → Test (⌘U), or filter
to just this suite via the Test Navigator ("MascotPoseEngineTests").

Command line (only if `xcodebuild test -scheme Cadence` completes in your
environment — see this plan's Global Constraints note on the watchOS
simulator issue):
```bash
xcodebuild test -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CadenceTests/MascotPoseEngineTests 2>&1 | tail -40
```

Expected: all 9 tests pass (`** TEST SUCCEEDED **`).

- [ ] **Step 6: Commit**

```bash
git add Cadence.xcodeproj/project.pbxproj Cadence/Services/MascotPoseEngine.swift CadenceTests/MascotPoseEngineTests.swift
git commit -m "Add MascotPoseEngine with full pose-priority test coverage"
```

---

### Task 4: Wire the engine into `publishWidgetSummary`

**Files:**
- Modify: `Cadence/Features/Dashboard/DashboardViewModel.swift`

**Interfaces:**
- Consumes: `MascotPoseEngine.pose(for:activeFlare:streakDays:)` (Task 3),
  `WidgetData.Summary.mascotPose` (Task 2).
- Produces: `DashboardViewModel.publishWidgetSummary(logs: [DailyLog], flares: [Flare] = [])`
  — the `flares` parameter is new; existing callers that don't pass it keep
  compiling unchanged (they get a flare-blind pose — see the code comment
  below for why that's an accepted tradeoff, not a bug).

- [ ] **Step 1: Widen `publishWidgetSummary` and wire `refresh` to it**

Open `Cadence/Features/Dashboard/DashboardViewModel.swift`. Find this exact
block:

```swift
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

        Self.publishWidgetSummary(logs: logs)
    }

    // Single publish point for the home-screen widget, callable from any save
    // path (dashboard refresh, watch quick-log, log flow). Skips the write AND
    // the timeline reload when nothing changed — reloads are system-budgeted,
    // and burning the budget on no-op refreshes leaves real changes stranded.
    static func publishWidgetSummary(logs: [DailyLog]) {
        let summary = WidgetData.Summary(
            date: Calendar.current.startOfDay(for: .now),
            loggedToday: logs.first { Calendar.current.isDateInToday($0.date) }?.isComplete == true,
            streak: computeStreak(from: logs)
        )
        guard summary != WidgetData.read() else { return }
        WidgetData.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
```

Replace it with:

```swift
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
    // `flares` defaults to `[]`: only `refresh` (the Dashboard's own full
    // refresh path) has flare data in scope for free. The other callers —
    // CadenceApp's foreground sweep, LogInputFlow's save, the watch/Siri
    // quick-log paths, and SyncBackupSection's restore — are narrow,
    // single-purpose paths; adding a Flare fetch to each just for the
    // mascot would be disproportionate for a decorative feature. They
    // publish with a flare-blind pose, which self-corrects on the next full
    // Dashboard refresh — the same brief-staleness tradeoff the widget
    // already accepts elsewhere (its interim "mood saved" state).
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

- [ ] **Step 2: Confirm every existing caller still compiles**

The other 6 callers of `publishWidgetSummary` pass only `logs:`, which
still works because of the new `flares: [Flare] = []` default. Confirm none
of them were passing a second positional/labeled argument that would now
conflict:

```bash
grep -rn "publishWidgetSummary(logs:" Cadence/ 2>/dev/null
```

Expected output — all 6 non-`refresh` call sites end in `)` right after
`logs: <expr>`, nothing else:
```
Cadence/App/CheckInIntents.swift:51:        DashboardViewModel.publishWidgetSummary(logs: logs)
Cadence/App/CadenceApp.swift:267:            DashboardViewModel.publishWidgetSummary(logs: logs)
Cadence/Features/Settings/SyncBackupSection.swift:128:            DashboardViewModel.publishWidgetSummary(logs: freshLogs)
Cadence/Features/DailyLog/LogInputFlow.swift:778:            DashboardViewModel.publishWidgetSummary(logs: logs)
Cadence/Services/PhoneConnectivityManager.swift:70:            DashboardViewModel.publishWidgetSummary(logs: logs)
```

If any line looks different from this pattern, stop and inspect it before
continuing — it may need an explicit `flares:` argument instead of relying
on the default.

- [ ] **Step 3: Build-check via the widget extension**

`DashboardViewModel.swift` itself isn't compiled into the widget extension,
so this specific file's correctness can't be confirmed that way — only
`WidgetData.swift` (Task 2) can be. Confirm this task's changes at least
parse correctly:

```bash
xcrun swiftc -parse Cadence/Features/Dashboard/DashboardViewModel.swift 2>&1 | grep -v "cannot find\|Cannot find" || echo "no non-import errors"
```

(`cannot find` / `Cannot find` errors here are expected noise from
single-file parsing without the rest of the module — CLAUDE.md documents
this same limitation for any environment without a full Xcode toolchain
build. A real compile check needs Xcode's ⌘B on the `Cadence` scheme.)

- [ ] **Step 4: Commit**

```bash
git add Cadence/Features/Dashboard/DashboardViewModel.swift
git commit -m "Wire MascotPoseEngine into publishWidgetSummary"
```

---

## What's deliberately not in this plan

- No `Image("mascot-<pose>")` in any view — Dashboard empty state, streak
  badge, widget rendering, onboarding, Insights empty state. Follow-up plan
  once art lands in `Assets.xcassets` (spec Sections 4 and 6, steps 6–8).
- No notification rich-attachment work (spec Section 8.3 — deferred, needs
  its own file-URL-based approach, not `Image("mascot-sleepy")`).
- No `DashboardViewModel.mascotPose` published property for the view layer
  to bind to — that's added alongside the view wiring above, not before
  anything reads it.

## Known follow-up item (found in final whole-branch review, 2026-07-22)

**`publishWidgetSummary`'s flare-blind callers can downgrade a correct
`.cozy` pose, not just lag it.** Task 4's `flares: [Flare] = []` default was
framed as "brief staleness" — the 6 non-`refresh` callers publish a
flare-blind pose that self-corrects on the next full Dashboard refresh. The
final review traced this further: for a user with an active flare who
quick-logs from the widget/watch/Siri, or who simply foregrounds the app
without opening the Dashboard, the flare-blind computation doesn't just fail
to *add* `.cozy` — it actively **overwrites an already-correct stored
`.cozy`** with `.soaking`/`.resting` (since `pose` is recomputed from scratch
each call, and the new value differs from what's stored, so the
`summary != WidgetData.read()` guard fires and republishes the worse pose).
For a widget-only quick-logger, that wrong pose then persists across
midnight via `resolved()`, not "almost immediately" as originally assumed.
(Mood-trend `.cozy` is unaffected — every flare-blind caller already fetches
full `DailyLog` history — only the flare arm is lost.)

This is **currently latent**: nothing in this plan renders `mascotPose`
anywhere, so no user sees it yet. It must be resolved as part of the
view-wiring follow-up, before that plan ships anything visible. Two options
the review suggested, in order of preference:

1. Fetch `Flare` in the three callers that already hold a `context` and
   fetch `DailyLog` anyway (`CadenceApp.swift`'s foreground sweep,
   `LogInputFlow.swift`'s save, `PhoneConnectivityManager.swift`'s watch
   quick-log) — `(try? context.fetch(FetchDescriptor<Flare>())) ?? []` is a
   one-line addition at each, zero new architectural surface.
2. Have flare-blind paths preserve the previously-stored `mascotPose`
   (read-modify-write against `WidgetData.read()`) instead of recomputing a
   potentially-worse one.

Also flagged, both genuinely minor and not blocking that follow-up either:
- `refresh` computes `hasLowMoodTrend` over a 90-day window; the
  unbounded-fetch callers compute it over full history — the mood-trend
  verdict can differ by which path last published, mild tension with "every
  surface agrees" (spec §7). Low practical impact; mood trends move slowly.
- A pre-upgrade persisted `WidgetData.Summary` (no `mascotPose` field) fails
  to decode as a whole struct, so the one-time migration blip resets
  `streak`/`loggedToday` too, not just the pose, until the next publish. A
  hand-rolled `Codable.init(from:)` with `decodeIfPresent` for `mascotPose`
  would avoid this if the blip ever proves user-visible enough to matter.
