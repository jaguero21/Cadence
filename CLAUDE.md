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
- **Medication reminders:** `Medication.reminderMinutes: [Int]` (minutes since
  midnight; `[]` = off) drives daily local notifications.
  `NotificationService.syncMedicationReminders(_:)` is a **reconcile sweep**:
  remove every pending request with `NotificationID.medicationPrefix`, then
  reschedule active meds — edits, deletions, renames, and ended courses all
  ride the same idempotent pass (no per-change bookkeeping). Called from the
  medication editor's save, the list's delete, and `ContentView` on foreground
  (which is what silences a course whose end date passed, or one removed on
  another device). The permission prompt only fires when a reminder actually
  exists. `medicationReminderID(name:minute:)` and the
  `Medication.minuteOfDay`/`timeToday` picker conversions are pure and
  unit-tested; reminders round-trip through `BackupService`.
- **Custom trackers:** `CustomTracker` (`@Attribute(.unique) id: UUID`, name,
  min/max, unit) defines user metrics; per-day values live on
  `DailyLog.customMetrics: [MetricEntry]` keyed by the tracker's stable `id` (so
  renames don't orphan history). Logged via slider rows appended to the Body
  Metrics step in `LogInputFlow`, managed in `CustomTrackersView`, averaged in
  the doctor PDF. Wired into `PatternEngine.trackerCorrelations` (mean-split
  high/low days vs symptom count; key is `tracker:<uuid>` so renames update the
  same insight) and into trend charts via `ChartSeries.custom` (days without an
  entry are skipped, never drawn as zero; the comparison badge is neutral
  because a custom tracker's desirable direction is unknowable).
- **Peaks & Valleys / Intentions for Tomorrow:** closing reflections. In the
  **daily log** they live (with the one-line note + attachments) on a single
  combined `.reflection` step — three consecutive text pages made the daily
  flow feel long; the fields stayed separate:
  `peaksAndValleysNote: String` + `peaksAndValleysVoiceMemo: Attachment?` +
  `intentionsForTomorrow: String` on `DailyLog`. The **weekly review** has
  only Intentions (`intentionsForTomorrow` on `WeeklyReview`) — a weekly
  Peaks & Valleys step shipped briefly and was removed after real use; don't
  reintroduce it. These are dedicated fields, not the generic `PromptResponse`
  system (text-only). Every reflection card carries the same photo/voice
  controls (`AttachmentControls` in `LogInputFlow`): attachments live in the
  one `DailyLog.attachments` array, tagged with `Attachment.section`
  (`peaksAndValleys` / `intentions` / nil = the note card, which also shows
  pre-tagging attachments). The legacy single-slot `peaksAndValleysVoiceMemo`
  field migrates into the pool on hydrate and is cleared on the next save;
  `DailyLogSnapshot.hasPeaksAndValleysVoiceMemo` checks both.
  `LogInputFlow` stages these like every other field (local `@State`, applied
  to the model at save time); `ReviewFlowView` binds directly to the `@Model`
  (`$review.intentionsForTomorrow`, matching how `overallRating` is already
  bound) since that flow doesn't stage. `WeeklyReviewViewModel.ReviewStep`
  (`.prompt(Int) / .intentions`) extends the flat prompt index into the extra
  step — `flatIndex`/`totalSteps` give every step (prompts included) one
  unified "N of 8" position. Surfaces in the doctor PDF (per-day, from
  `DailyLogSnapshot`), the personal PDF (per-week Intentions, from
  `WeeklyReviewSnapshot`), and the CSV export; voice memo binaries are never
  backed up (`BackupService` carries only the text fields, same rule as
  `attachments`).
- **Insight history & notifications:** every `InsightCard` carries a **stable
  semantic `key`** (e.g. `med-effect:Sertraline`) set at the PatternEngine
  creation site — never derive identity from the display title, which changes
  (direction flips, copyedits, localization). `InsightRecord`s dedupe by that
  key via `InsightRecorder.record(_:context:)`, which updates copy/confidence
  in place, skips no-op saves, reports save failures via OSLog (returning `[]`
  so nothing unpersisted is announced as new), and returns only newly-emerged
  records. `InsightRecorder.currentInsights/detectAndRecord` is the **canonical
  pipeline** (90-day window, `PatternThreshold.insightWindowDays`) used by both
  the Insights tab and `ContentView.checkForNewInsights()` (Pro only, throttled
  to once per calendar day via `UserDefaultsKey.lastInsightCheckDay`) so the
  surfaces can never disagree about which patterns exist.
- **Flares:** `Flare` (`startDate`/optional `endDate`/`peakSeverity`/`note`) tracks
  multi-day symptom episodes; `durationDays` is inclusive and counts ongoing
  flares through today. Managed in `FlaresView` (Settings → Flares) and listed in
  the doctor PDF. `PatternEngine.flarePrecursors` compares the
  `flarePrecursorWindowDays` run-up before each flare against baseline days
  (in-flare days excluded from both sides) and surfaces stress-rise
  (`flare-stress`), sleep-dip (`flare-sleep`), overnight wrist-temperature
  rise (`flare-temp`), and overnight respiratory-rate rise
  (`flare-respiratory`) early-warning cards (the HealthKit-fed ones use
  `hkWristTemp`/`hkRespiratoryRate`; only days carrying a measurement
  participate); needs `minimumFlaresForPattern` flares with run-up data.
  `daylightMoodCorrelation` (`daylight-mood`) mirrors mood-sleep for
  HealthKit's time-in-daylight — only the actionable direction (more daylight
  → better mood) surfaces.
- **Workout detail:** `DailyLog.hkWorkoutMinutes` (total workout duration; nil
  = no workouts, so a "workout day" is inferable but missing-data never is) is
  fetched by `fetchWorkoutDetail` alongside the `intenseWorkout` gate that
  auto-selects the "Intense exercise" factor chip. Two one-direction-only
  detectors: `workoutMoodCorrelation` (`workout-mood`, workout days → better
  mood) and `workoutRecoveryPattern` (`workout-recovery`, MORE symptoms the
  day after a workout, consecutive-day pairs only — the "fewer symptoms"
  direction is suppressed because it reads as exercise advice). Charted via
  `ChartSeries.workoutMinutes(longestSession:)` (neutral badge, shown only
  when the window has a workout); in LogDetailView, doctor PDF, CSV, backup
  like every `hk*` field.
- **HealthKit is always optional.** HK values only prefill or supplement —
  the sleep sliders, the "Menstrual cycle" factor chip (auto-selected via
  `LogInputFlow.menstrualCycleFactorName` when Health has a flow entry today),
  and the `hk*` objective fields. Nothing is gated on Health access, prefills
  never overwrite user-entered values (`didEditMetrics` guard), and every
  loggable variable stays fully manual. Every type in
  `HealthKitService.readTypes` must be fetched by `fetchLogSnapshot` —
  requesting permission for data that's never read is a broken promise.
- **Health two-way sync:** `HealthKitService.publish(log:)` (called from
  `LogInputFlow` after every successful save, fire-and-forget) mirrors the
  day into Health — mapped symptoms as severity samples, and the mood as a
  State of Mind daily-mood entry (iOS 18+, only when `didEditMood`).
  Delete-then-write per type keeps re-saves idempotent; HK can only delete
  our own samples, so other apps' data is untouchable by construction.
  Reads exclude our own bundle's samples (else a symptom removed in Cadence
  would resurrect from Health). The name↔type/severity/valence maps are pure
  statics on `HealthKitService` (`symptomTypeByName` etc.), unit-tested; only
  honest mappings — a Cadence symptom with no real HK counterpart (e.g.
  "Brain Fog") simply doesn't sync.
- **HealthKit freshness:** `HealthDataRefresher.refreshToday` tops up TODAY's
  existing log's `hk*` fields (via the shared
  `DailyLog.applyObjectiveHealthData`, which never blanks a value on nil and
  never touches user-entered fields) — it **never creates a log** (no phantom
  entries from background data). Driven by `HealthKitService
  .startObservingChanges` (HKObserverQuery + hourly background delivery;
  entitlement `com.apple.developer.healthkit.background-delivery`) started in
  `CadenceApp`, with a foreground fallback in `ContentView`'s scenePhase
  handler.
- **Symptom library:** `SymptomTag.optionalCatalog` (~34 entries) is the
  toggleable symptom list in Settings → Symptoms (`SymptomLibraryView`, free —
  only free-text custom symptoms are Pro). A toggle inserts/deletes the
  `SymptomTag` row itself (name-deduped at save time), not an `isEnabled`
  flag, so the picker's `@Query` is untouched. Every catalog name must resolve
  via `HealthKitService.symptomTypeIdentifier` (unit-test-pinned) so enabled
  symptoms sync two-way with Health; history survives toggling off via the
  picker's unlisted-chip rendering.
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
  `[InsightCard]` **sorted strongest-first** (the dashboard headline takes
  `.first`, so it must be the strongest signal, not detector order).
  Confidence for proportion-based patterns uses the **Wilson score lower
  bound** (`wilsonLowerBound`); every mean-comparison detector runs through
  the shared `compareMeans` + `comparativeConfidence` helpers — confidence =
  effect × n/(n + `smallSampleShrinkage`) on the comparison's THINNER side, so
  the same delta over 4 days can't display the same confidence as over 40.
  Don't hand-roll a two-group comparison or a `min(delta/scale, 1)` confidence
  in a new detector. The framing is awareness, not diagnosis: the Insights tab
  and the doctor PDF both carry a "not medical advice" disclaimer next to the
  pattern cards.
- **Date-windowed views** (`DashboardView`, `DailyLogView`, `WeeklyReviewView`,
  `InsightsView`) take a `referenceDate` and derive their `@Query` cutoff from
  it. `ContentView` passes `today` (refreshed on `scenePhase == .active`) so a
  midnight rollover re-inits the child with a new window — updating the `@Query`
  in place. Do **not** reintroduce `.id(dayId)`: changing identity tears the
  subtree down and drops open sheets / scroll state.
- **Persistence resilience.** `sharedModelContainer` tries a **CloudKit-mirrored**
  store first (`cloudKitDatabase: .automatic`), then a local-only persistent
  store (used when the iCloud entitlement is absent), then in-memory, then
  `StorageFatalErrorView`. `save()` methods return `Bool`, revert mutated state
  on failure, and surface a `saveError`; orphan/rollback cleanup at `.onDisappear`.
- **CloudKit constraints.** Because of CloudKit mirroring, models carry **no
  `@Attribute(.unique)`** and every non-optional attribute has an **inline default
  value** (both are hard CloudKit requirements). Uniqueness/dedup is enforced in
  code **at save time, not just at presentation time** — a sheet's captured
  `existingLog`/`existingReview` can go stale while it's open (watch quick-log,
  CloudKit import): `LogInputFlow.ensureLog()` re-fetches today's log before
  creating one, `WeeklyReviewViewModel.save` merges into a persisted same-week
  review, `seedSymptomTagsIfNeeded` dedupes by name against the store, and
  `InsightRecorder` dedupes by key. Don't reintroduce `.unique`, drop the inline
  defaults, or add an insert path without a save-time dedup check.

## Conventions

- **Logging:** `OSLog` — `Logger(subsystem: "com.carpecadence", category: "...")`.
- **Styling:** colors via `CadenceColor` (asset catalog), animations via
  `CadenceAnimation`, tunable thresholds in `Shared/Constants.swift`
  (`PatternThreshold`, etc.). Don't hardcode these inline.
- **Haptics:** `UINotificationFeedbackGenerator().notificationOccurred(...)` on
  successful saves.

## iPad

- The app + unit-test targets are `TARGETED_DEVICE_FAMILY = "1,2"`; iPhone is
  portrait-only, iPad supports all four orientations
  (`UISupportedInterfaceOrientations~ipad`) — required, since
  `UIApplicationSupportsMultipleScenes` is on (Stage Manager resizing).
- **One layout, adapted — no forked iPad views.** Scrolling card columns get
  `.readableColumn()` (caps at `CadenceLayout.readableColumnWidth`, centered)
  on the padded VStack inside the ScrollView; the TabView gets
  `.adaptableTabBar()` (iOS 18 `.sidebarAdaptable` — top bar/sidebar on iPad,
  classic bottom bar on iPhone). Apply `.readableColumn()` to any NEW
  scrolling card screen.
- `InsightsView` is the exception: its column caps at `insightsColumnWidth`
  and charts + insight cards flow through `gridColumns` (2-up when
  `horizontalSizeClass == .regular`, single column otherwise). Lists/Forms
  (Weekly Review, Settings) stay native full-width; sheets are system form
  sheets on iPad and need no width handling.

## Widget

- `CadenceWidgetExtension` (folder `CadenceWidget/`, a synchronized file-system
  group — files there auto-build for the widget, unlike the app target's explicit
  references). Shows logging streak + today's check-in status.
- App↔widget share via the **App Group** `group.com.carpecadence.app`:
  `WidgetData` (in `CadenceWidget/WidgetData.swift`, added to *both* targets —
  explicit ref for the app, sync group for the widget) writes/reads a small
  `Summary` in the shared `UserDefaults` suite.
  `DashboardViewModel.publishWidgetSummary(logs:)` is the **single publish
  point** — call it from any path that saves a `DailyLog` (dashboard refresh,
  `LogInputFlow.partialSave`, watch quick-log). It skips the write *and* the
  timeline reload when the summary is unchanged (reloads are system-budgeted);
  never call `WidgetCenter.reloadAllTimelines()` without republishing first.
  The widget's `Provider` validates `summary.date` before trusting it:
  `loggedToday` only holds for a summary from today, and a streak survives
  exactly one day past its summary.
- App bundle id is **`com.carpecadence.app`** (unified with the code's
  `com.carpecadence` convention); widget is `com.carpecadence.app.CadenceWidget`.
- **Interactive mood buttons** (`WidgetQuickLogIntent` in
  `CadenceWidget/QuickLogIntent.swift`, member of both app and widget targets):
  the widget can't open the app's SwiftData store, so a tap is **stashed** in
  the App Group (`WidgetData.stashPendingQuickLog`, date-stamped, queue capped)
  and the widget shows an interim "Mood saved" state. The app consumes the
  queue on foreground (`ContentView.applyPendingQuickLogs`) through the same
  `applyQuickLog` upsert seam the watch uses — so an overnight tap lands on
  the day it was made — then republishes the summary AND explicitly reloads
  the timeline (the summary is usually unchanged, since a quick log doesn't
  complete the day, and the skip-if-unchanged guard would strand the interim
  state). Widget kind string lives in `WidgetData.widgetKind`.
- **Control Center button** (`CheckInControl`, iOS 18): one tap opens the app
  straight into today's log — deliberately NOT a "log a default mood" button
  (unchosen data is fake awareness). The control stashes an open request via
  `WidgetData.requestCheckInOpen` (controls run in the extension process);
  `ContentView.openCheckInIfRequested` consumes it on foreground and presents
  `LogInputFlow` directly.
- **Lock Screen / StandBy**: the same widget also serves `accessoryCircular`
  / `accessoryRectangular` / `accessoryInline` (per-family switch in
  `CadenceWidgetEntryView`). Circular/rectangular are wrapped in
  `Button(intent: OpenCheckInIntent())` — tap goes straight into today's log
  via the Control Center stash; they never log by themselves. Key content is
  `.widgetAccentable()` for tinted/vibrant rendering. StandBy just shows the
  `systemSmall` family. The widget extension's deployment target is 26.4
  (the app's is 17.0), so iOS 18 APIs need no gating inside `CadenceWidget/`.

## App Intents (Siri / Shortcuts)

- `LogCheckInIntent` (`Cadence/App/CheckInIntents.swift`, app target only) is
  the Siri/Shortcuts check-in: mood (`MoodOption` AppEnum, emoji order matches
  `MoodScale`) + optional energy. It runs in the app's process and writes via
  `PhoneConnectivityManager.applyQuickLog` + `publishWidgetSummary` — every
  quick-log surface (watch, widget, Siri) funnels through that one tested
  upsert. Phrases live in `CadenceShortcuts: AppShortcutsProvider`.
- `CadenceApp.sharedModelContainer` is **static** so intents (which run outside
  the SwiftUI scene) reach the same container the UI uses.

## Watch app

- `CadenceWidget Watch App` target (folder of the same name, a synchronized
  group) provides a wrist **quick-log**: mood + energy → "Save to iPhone".
- Bridge is **WatchConnectivity** (App Groups don't cross devices). The watch's
  `WatchConnectivityManager` sends a plain `[String: Any]` payload
  (`mood`/`energy`/`date`) via `sendMessage` with a reply ack, falling back to
  `transferUserInfo`; the UI reports **Sent** (acked) vs **Queued** truthfully,
  and the session is activated at watch-app launch to avoid racing the first
  tap. The phone's `PhoneConnectivityManager` (started in `CadenceApp` with the
  container) **upserts the log for the payload's `date`** — a queued overnight
  entry lands on the day it was recorded, never clobbering the new day — then
  republishes the widget summary. No model types are shared across the targets;
  `MoodScale` (in the watch folder, member of both targets) keeps the emoji
  scale identical on both sides.
- Watch deployment target is 26.2; live phone↔watch transfer needs paired
  sims/devices to verify (compiles + structurally complete here).

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

- `TrendChartView` draws a `ChartSeries` (label/color/domain + a per-log value
  extractor returning `nil` for no-data days) with an `average` `RuleMark`
  annotation and a period-comparison badge: it takes the current window's `logs`
  plus the equal-length `previousLogs` window (computed in `InsightsView`) and
  shows the delta. Built-ins map via `ChartMetric.series` (stress is inverted —
  lower is better); custom trackers via `ChartSeries.custom`, whose
  `higherIsBetter` is `nil` → neutral badge. Badge threshold in
  `ChartThreshold`. `TrendChartView.mean`, `ChartMetric.isImprovement`, and
  `ChartSeries.isImprovement` are the pure, unit-tested helpers.
- `InsightsView`'s `@Query` spans **2× the largest chart window** (180 days) so
  `previousLogs` has data for the 90D comparison; keep it at 2× if ranges
  change (`ChartRange.days` is the per-range source of truth). Insight
  computation still uses the canonical 90-day slice (`insightLogs`).

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
  writes the temp file). Both are driven from `ExportView`; PDFs open in
  `ReportPreviewSheet` (PDFKit) with sharing in its toolbar — never straight
  into a blind share sheet — while the CSV still uses `ShareSheet`.
- `PDFBuilder` layout goes through the private `Cursor` class (page breaks,
  per-page footer with page number + disclaimer, `section`/`line`/`bar`
  primitives) — don't hand-place `y` offsets in renderers. Both report types
  open with a shared header (date range, "N of M days logged", generated
  date) and a **Trends** grid of Swift Charts images rendered via
  `ImageRenderer` on the MainActor *before* the PDF context opens (mood,
  energy, sleep quality, anxiety; skipped under 2 logs). Print inks come from
  `printColor(_:fallback:)`, which resolves catalog colors for LIGHT mode —
  a report generated on a dark-mode phone must not use dark-variant colors.
  Symptom frequency renders as proportional bars carrying avg severity.
  The Export screen's "Includes" list must stay truthful to what the PDFs
  actually contain.
- "Appointment" flow: `UserDefaultsKey.lastVisitDate` stores a visit anchor
  (`timeIntervalSinceReferenceDate`, 0 = unset) so a report can be scoped to
  everything since the last visit.

## Backup & iCloud status

- **JSON backup/restore** (`BackupService`, driven from `SyncBackupSection` in
  Settings; intentionally **not Pro-gated** — users own their data). The
  versioned `Document` mirrors the user-entered models; insight history is
  recomputable and attachment binaries live outside SwiftData, so neither is
  included. `encode`/`decode` are pure and unit-tested (ISO8601 dates; decode
  rejects documents from a newer format version). **Restore merges** — inserts
  what the store lacks, never overwrites (logs by day, reviews by week start,
  tags by name, meds by name+start, flares by start, trackers by `id`).
  `CustomTracker.id` must round-trip: `DailyLog.customMetrics` is keyed by it.
  Restore republishes the widget summary (it can change today's streak).
- **Sync status**: `CloudSyncMonitor` (@MainActor singleton) folds
  `NSPersistentCloudKitContainer.eventChangedNotification` events (SwiftData's
  mirroring is built on that container) plus the CloudKit account status into
  one `SyncState`. `CadenceApp.usingCloudKitStore` records whether the
  CloudKit-backed store actually initialised (vs the local fallback) so the row
  reads "Off — local storage" truthfully. The state fold (`stateAfterEvent`) is
  pure and unit-tested; sync events outrank the account probe.

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
  `#require`. Exception: **`CadenceUITests` is XCTest** (XCUIApplication has no
  Swift Testing equivalent). The smoke test launches with `--uitest`, which
  gives the app an in-memory store, fresh onboarding, and no permission
  prompts (`AppLaunch.isUITesting`) — keep new UI-affecting launch behavior
  behind that flag so UI runs stay deterministic.
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
