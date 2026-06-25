# Cadence

A SwiftUI + SwiftData iOS app (iOS 17+) for daily symptom/mood/energy logging,
weekly reviews, pattern insights, HealthKit import, and PDF export.

## Architecture

- **MVVM-ish.** Views own `@State` view models (`@Observable`, `@MainActor`).
  View models hold transient flow state and `save(...)` logic; SwiftData
  `@Model`s hold persisted data.
- **Models** (`Cadence/Models/`): `@Model` classes `DailyLog`, `WeeklyReview`,
  `SymptomTag`, `Medication`. The schema is declared in
  `CadenceApp.sharedModelContainer`.
- **Medication correlation:** `Medication` has a `startDate`/`endDate`;
  `PatternEngine.medicationEffects` compares average daily symptom count before
  vs after the start date and surfaces an `.symptom` `InsightCard`. Medications
  flow into both the in-app Insights tab and the doctor PDF.
- **Custom trackers:** `CustomTracker` (`@Attribute(.unique) id: UUID`, name,
  min/max, unit) defines user metrics; per-day values live on
  `DailyLog.customMetrics: [MetricEntry]` keyed by the tracker's stable `id` (so
  renames don't orphan history). Logged via slider rows appended to the Body
  Metrics step in `LogInputFlow`, managed in `CustomTrackersView`, averaged in
  the doctor PDF. Not yet wired into trend charts or `PatternEngine` (those are
  hardcoded to the built-in fields) — a known follow-up.
- **Insight history & notifications:** detected `InsightCard`s are persisted as
  `InsightRecord` (deduped by title) via `InsightRecorder.record(_:context:)`,
  which returns only the newly-emerged ones. `InsightsView` records on appear and
  links to `InsightHistoryView`; `ContentView.checkForNewInsights()` runs on
  foreground (Pro only) and fires `sendInsightNotification` for the top new
  high-confidence pattern. Recording is idempotent, so users are notified once
  per pattern.
- **Flares:** `Flare` (`startDate`/optional `endDate`/`peakSeverity`/`note`) tracks
  multi-day symptom episodes; `durationDays` is inclusive and counts ongoing
  flares through today. Managed in `FlaresView` (Settings → Flares) and listed in
  the doctor PDF.
- **Factor (trigger) logging:** `DailyLog.factors: [String]` holds contextual
  triggers chosen from a fixed list (`LogInputFlow.factorItems`) in the `.factors`
  log step — same hardcoded-list pattern as `basicsCompleted` (no model).
  `PatternEngine.factorCorrelations` compares average daily symptom count on days
  with vs without each factor and surfaces likely triggers. Factor frequency also
  appears in the doctor PDF.
- **Snapshots.** `DailyLogSnapshot` / `WeeklyReviewSnapshot` are `Sendable`
  structs that live **next to their model** in `Models/`. They are plain-value
  projections of the `@Model`s so `PatternEngine` and PDF export can run off any
  isolation context — `@Model`s are not `Sendable` and would race on their
  SwiftData-backed fields. Build a snapshot from a model; never pass a `@Model`
  across actors.
- **Services behind protocols** (`Cadence/Services/`): concrete services are
  `@MainActor` singletons (`HealthKitService.shared`, `NotificationService.shared`).
  Views/view models depend on the protocols (`HealthKitServiceProtocol`,
  `NotificationServiceProtocol`, `ModelPersisting`), injected via
  `@Environment` or defaulted init params, so tests can pass fakes.
  `ModelPersisting` is a seam over `ModelContext` (insert/delete/save) so save
  failure paths can be tested with a throwing stub.
- **PatternEngine** is a stateless `enum`: takes `[DailyLogSnapshot]`, returns
  `[InsightCard]`. Confidence for proportion-based patterns uses the **Wilson
  score lower bound** (`wilsonLowerBound`), not the raw hit/total ratio, so a
  small sample can't read as 100% certain. The user-facing copy shows the raw
  observed frequency; the card's `confidence` is the Wilson bound.
- **Date-windowed views** (`DashboardView`, `DailyLogView`, `WeeklyReviewView`,
  `InsightsView`) take a `referenceDate` and derive their `@Query` cutoff from
  it. `ContentView` passes `today` (refreshed on `scenePhase == .active`) so a
  midnight rollover re-inits the child with a new window — updating the `@Query`
  in place. Do **not** reintroduce `.id(dayId)`: changing identity tears the
  subtree down and drops open sheets / scroll state.
- **Persistence resilience.** `sharedModelContainer` falls back to in-memory
  storage if the persistent store fails, then to `StorageFatalErrorView` if even
  that fails. `save()` methods return `Bool`, revert mutated state on failure,
  and surface a `saveError`; orphan/rollback cleanup happens at `.onDisappear`.

## Conventions

- **Logging:** `OSLog` — `Logger(subsystem: "com.carpecadence", category: "...")`.
- **Styling:** colors via `CadenceColor` (asset catalog), animations via
  `CadenceAnimation`, tunable thresholds in `Shared/Constants.swift`
  (`PatternThreshold`, etc.). Don't hardcode these inline.
- **Haptics:** `UINotificationFeedbackGenerator().notificationOccurred(...)` on
  successful saves.

## Widget

- `CadenceWidgetExtension` (folder `CadenceWidget/`, a synchronized file-system
  group — files there auto-build for the widget, unlike the app target's explicit
  references). Shows logging streak + today's check-in status.
- App↔widget share via the **App Group** `group.com.carpecadence.app`:
  `WidgetData` (in `CadenceWidget/WidgetData.swift`, added to *both* targets —
  explicit ref for the app, sync group for the widget) writes/reads a small
  `Summary` in the shared `UserDefaults` suite. `DashboardViewModel.refresh`
  writes it and calls `WidgetCenter.reloadAllTimelines()`.
- App bundle id is **`com.carpecadence.app`** (unified with the code's
  `com.carpecadence` convention); widget is `com.carpecadence.app.CadenceWidget`.

## Attachments

- `DailyLog.attachments: [Attachment]` holds lightweight references; binaries live
  on disk via `AttachmentStore` (Documents/Attachments, base dir injectable for
  tests). Photos are added in the log's note step via `PhotosPicker` (no
  permission prompt) and shown in `LogDetailView`.
- Voice notes (`AttachmentKind.audio`) record via `AudioRecorder` and play via
  `AudioPlaybackButton`/`AudioPlayback` (all in `Features/DailyLog/VoiceNote.swift`,
  built on `AVAudioRecorder`/`AVAudioPlayer`). Needs `NSMicrophoneUsageDescription`
  (in Info.plist). Compiles and drives the permission flow; **actual capture
  should be verified on a device.**

## Charts

- `TrendChartView` draws each metric with an `average` `RuleMark` annotation and a
  period-comparison badge: it takes the current window's `logs` plus the
  equal-length `previousLogs` window (computed in `InsightsView`) and shows the
  delta, colored by `ChartMetric.isImprovement(delta:)` (stress is inverted —
  lower is better). `TrendChartView.mean` and `ChartMetric.isImprovement` are the
  pure, unit-tested helpers.

## History

- `HistoryView` shows a month calendar by default; when a search term or a
  `HistoryFilter` (all / completed / in progress / has symptoms) is active it
  switches to a flat all-time results list. The match predicate is the pure
  static `HistoryView.logMatches(...)` (unit-tested) — keep filtering logic there,
  not inline, so it stays testable. `LogDetailView` shows metrics, symptoms,
  factors, notes, and HealthKit data.

## Export

- The doctor/personal PDF is built by `PDFBuilder`; a spreadsheet export is built
  by `CSVBuilder` (`csvString(from:)` is the pure, testable core; `build(logs:)`
  writes the temp file). Both are driven from `ExportView` and shared via
  `ShareSheet`.
- "Appointment" flow: `UserDefaultsKey.lastVisitDate` stores a visit anchor
  (`timeIntervalSinceReferenceDate`, 0 = unset) so a report can be scoped to
  everything since the last visit.

## Localization

- Strings live in `Cadence/Localizable.xcstrings`. `SWIFT_EMIT_LOC_STRINGS` is
  on, so Xcode **auto-extracts** keys into the catalog on build — you rarely
  hand-edit the `.xcstrings` JSON.
- `Text("a literal")` is already localized (it takes `LocalizedStringKey`). No
  change needed; it extracts automatically.
- **The gap to watch:** `Text(someStringVariable)` uses the non-localizing
  `StringProtocol` initializer. For any user-facing `String` (e.g. a view
  model's `saveError`, an `errorMessage`), build it with
  `String(localized: "...")` at the assignment site so it extracts and
  localizes; then `Text(thatString)` displays the already-localized value.
- Not yet migrated: debug-only copy behind the simulated-data tooling in
  `SettingsView` (the `seedResultMessage` interpolations) — intentionally left.

## Testing

- **Swift Testing**, not XCTest: `import Testing`, `@Suite`, `@Test`, `#expect`,
  `#require`. (XCTest is not used.)
- SwiftData tests use an **in-memory `ModelContainer`** built from the same
  `Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, Medication.self])`.
- Any suite that calls a `@MainActor` singleton (e.g. `NotificationService.shared`)
  must itself be annotated `@MainActor`, or it won't compile.
- Inject fakes that conform to the service protocols; use `ThrowingPersistence`
  (a `ModelPersisting` whose `save()` throws) to cover save-failure branches.

## Project file — IMPORTANT

- `Cadence.xcodeproj/project.pbxproj` uses **explicit file references**, not
  synchronized file-system groups. A **new `.swift` file is not in the build
  until added to `project.pbxproj`** — four entries: a `PBXBuildFile`, a
  `PBXFileReference`, the group's `children`, and the target's Sources build
  phase. Copy an existing file's four entries and give it fresh unique IDs.
- **Do not run `generate_project.rb`.** It is stale: it regenerates only the
  **app** target and would wipe the hand-added **test** target.

## Build / test

- Build & run tests in Xcode with ⌘U (scheme `Cadence`, test plan
  `Cadence.xctestplan`).
- Some environments have only the Command Line Tools (no `xcodebuild`/`Xcode.app`);
  there you can edit but not compile. SourceKit then reports spurious
  "Cannot find type ..." / "SwiftDataMacros ... plugin not found" diagnostics
  for cross-file and macro references — treat those as indexer noise, not errors.
