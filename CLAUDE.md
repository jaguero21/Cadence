# Cadence

A SwiftUI + SwiftData iOS app (iOS 17+) for daily symptom/mood/energy logging,
weekly reviews, pattern insights, HealthKit import, and PDF export.

## Architecture

- **MVVM-ish.** Views own `@State` view models (`@Observable`, `@MainActor`).
  View models hold transient flow state and `save(...)` logic; SwiftData
  `@Model`s hold persisted data. Only 4 features have a dedicated
  `<Feature>ViewModel.swift` (`Insights`, `DailyLog`, `Dashboard`,
  `WeeklyReview`) — others (Settings, Export, History, Onboarding) keep state
  inline in the View. Extract a separate ViewModel file once the view owns
  non-trivial save or multi-step flow logic; don't for a view that just binds
  to `@Model` properties or toggles local UI state.
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
- **HealthKit data lives in a SEPARATE LOCAL-ONLY STORE — IMPORTANT.** All
  twelve `hk*` values live on `HealthSnapshot` (`Models/HealthSnapshot.swift`),
  not on `DailyLog`. `CadenceApp.sharedModelContainer` builds ONE container from
  TWO configurations: an unnamed CloudKit-mirrored one holding the user-entered
  models, and a `"LocalHealth"` one with `cloudKitDatabase: .none`. The reason is
  App Review Guideline 5.1.3(ii) — "may not store personal health information in
  iCloud" — and HealthKit-sourced values are the least defensible thing to put
  there. **Never add an `hk*` field back to `DailyLog`, and never move
  `HealthSnapshot` into the synced schema.** The synced configuration stays
  UNNAMED on purpose: naming it changes the store filename off `default.store`
  and reads as total data loss on upgrade.
  SwiftData cannot relate models across stores, so the two are joined by
  midnight-normalized `date` in exactly one place —
  `DailyLogSnapshot.build(from:in:)`. Every consumer of `hk*` data
  (`PatternEngine`, `PDFBuilder`, `CSVBuilder`, the trend charts) still takes
  `DailyLogSnapshot` and is otherwise unchanged; they just need snapshots built
  through that helper instead of `map(DailyLogSnapshot.init)`. Writes go through
  `HealthSnapshot.upsert(_:on:in:)` (save-time dedup by date, never blanks a
  value on nil, refuses to create an empty row).
- **Workout detail:** `HealthSnapshot.hkWorkoutMinutes` (total workout duration;
  nil = no workouts, so a "workout day" is inferable but missing-data never is)
  is fetched by `fetchWorkoutDetail` alongside the `intenseWorkout` gate that
  auto-selects the "Intense exercise" factor chip. That gate reads iOS 27's
  heart-rate zones (`workout.zoneGroup(for:)`, not the Optional
  `zoneGroupsByType` dictionary): 10+ minutes (`HealthThreshold
  .intenseZoneMinutes`) in the **top two zones the person configured** — by
  index, since zone counts differ between people. Zones decide alone when a
  workout reports them, so a long easy session no longer counts and a short hard
  one does; days without zone data (iOS 26, no heart-rate monitor, a
  hand-entered workout) keep the original 45-minute-or-400-kcal rule. That's why
  both `isIntenseExercise` overloads exist and are tested. Zone structs convert
  to plain `(index, minutes)` pairs inside `fetchWorkoutDetail` because they have
  no public initializers — logic holding them directly couldn't be unit-tested —
  and `zoneMinutes` stays nil rather than 0 when nothing reported zones, so
  absent data never reads as "no time up high". Heart rate only: cycling power
  zones would need a read type Cadence doesn't request, and every requested type
  must be fetched. Two one-direction-only
  detectors: `workoutMoodCorrelation` (`workout-mood`, workout days → better
  mood) and `workoutRecoveryPattern` (`workout-recovery`, MORE symptoms the
  day after a workout, consecutive-day pairs only — the "fewer symptoms"
  direction is suppressed because it reads as exercise advice). Charted via
  `ChartSeries.workoutMinutes(longestSession:minutesByDay:)` (neutral badge,
  shown only when the window has a workout; the per-day map is passed in and
  scoped to the visible range, since a log no longer carries the value); in
  LogDetailView, doctor PDF, CSV, backup like every `hk*` field.
- **A new read type is invisible to existing users until they re-authorize.**
  HealthKit never reveals whether READ access was granted
  (`authorizationStatus` reports sharing only), and a type added in an update
  stays undetermined until `requestAuthorization` runs again — which only
  happens in onboarding or Settings → Re-authorize HealthKit. So Settings shows
  a note when `HealthKitService.hasUnrequestedTypes()` says asking would prompt
  for something new (`statusForAuthorizationRequest(toShare:read:)` ==
  `.shouldRequest`). It READS status and never requests: onboarding is still the
  only place that prompts. The note is self-maintaining — add a read type in a
  future release and it appears on its own.
- **HealthKit is always optional.** HK values only prefill or supplement —
  the sleep sliders, the "Menstrual cycle" factor chip (auto-selected via
  `LogInputFlow.menstrualCycleFactorName` when Health has a flow entry today),
  and the `hk*` objective fields. Nothing is gated on Health access, prefills
  never overwrite user-entered values (`didEditMetrics` guard), and every
  loggable variable stays fully manual. Every type in
  `HealthKitService.readTypes` must actually be fetched somewhere — requesting
  permission for data that's never read is a broken promise. `fetchLogSnapshot`
  covers all of them except `menopausalState`, which `fetchMenopausalState`
  reads across all time rather than per day (see Menopausal state below).
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
  `HealthSnapshot` row (via `HealthSnapshot.apply`, which never blanks a value
  on nil and never touches user-entered fields) — it **never creates a log**
  (no phantom entries from background data), and for the same reason writes no
  health row for a day with no log at all. The `DailyLog` fetch survives purely
  as that gate. Driven by `HealthKitService
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
  picker's unlisted-chip rendering. The five seeded defaults are
  `SymptomTag.defaultSeeds` (plain name/emoji values; order = `sortOrder`);
  `seedSymptomTagsIfNeeded` inserts fresh models from `makeDefaults()`. See
  "Never hold `@Model` instances in a `static`" under Code quality conventions.
- **Factor (trigger) logging:** `DailyLog.factors: [String]` holds contextual
  triggers chosen from a fixed list (`LogInputFlow.factorItems`) in the `.factors`
  log step — same hardcoded-list pattern as `basicsCompleted` (no model).
  `PatternEngine.factorCorrelations` compares average daily symptom count on days
  with vs without each factor and surfaces likely triggers. Factor frequency also
  appears in the doctor PDF.
- **Snapshots.** `DailyLogSnapshot` / `WeeklyReviewSnapshot` are `Sendable`
  structs that live **next to their model** in `Models/`. They are plain-value
  projections of the `@Model`s so `PatternEngine` and PDF export can run off any
  isolation context — `@Model`s' `Sendable` conformance is macro-synthesized,
  not a real safety guarantee (see Code quality conventions), so they'd still
  race on their mutable, `ModelContext`-bound fields if passed across actors.
  Build a snapshot from a model; never pass a `@Model` across actors.
- **Services behind protocols** (`Cadence/Services/`): concrete services are
  `@MainActor` singletons (`HealthKitService.shared`, `NotificationService.shared`).
  Views/view models depend on the protocols (`HealthKitServiceProtocol`,
  `NotificationServiceProtocol`, `ModelPersisting`), injected via
  `@Environment` or defaulted init params, so tests can pass fakes.
  `ModelPersisting` is a seam over `ModelContext` (insert/delete/save) so save
  failure paths can be tested with a throwing stub. `HealthKitServiceProtocol`
  refines `Sendable` so `LogInputFlow.applyHealthKitData`'s task group can
  capture `any HealthKitServiceProtocol` under Swift 6. Conformers pay nothing
  for it: the protocol is `@MainActor`, so every conforming class is already
  `Sendable`.
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
  subtree down and drops open sheets / scroll state. This is the required
  shape for **any** new date-scoped `@Query` over `DailyLog`/`WeeklyReview`: a
  `referenceDate: Date = .now` init param binding `_logs = Query(filter:
  #Predicate<DailyLog> { $0.date >= cutoff }, ...)` in `init` — see
  `DashboardView` (90d), `DailyLogView` (30d), `WeeklyReviewView` (14d),
  `InsightsView` (180d). Unbounded `@Query` is only for small reference
  tables (`SymptomTag`, `CustomTracker`, `Medication`, `Flare`) or
  DEBUG-only tooling, not log/review data. **`HealthSnapshot` counts as
  per-day data**, so its `@Query` is windowed to match the logs it joins
  against — 90d in `DashboardView`, 180d in `InsightsView`, and a single
  `$0.date == day` predicate in `LogDetailView`, which needs exactly one row
  and used to materialise the whole table to search it in Swift.
- **Persistence resilience.** `sharedModelContainer` tries a **CloudKit-mirrored**
  synced store first (`cloudKitDatabase: .automatic`), then a local-only
  persistent one (used when the iCloud entitlement is absent), then in-memory,
  then `StorageFatalErrorView`. The `"LocalHealth"` configuration is paired into
  every tier — health data is already local, so only the synced half changes
  behaviour across the fallbacks. `save()` methods return `Bool`, revert mutated
  state on failure, and surface a `saveError`; orphan/rollback cleanup at
  `.onDisappear`. Each tier is **`do`/`catch`, never `try?`** — the thrown error
  is the only account of why the store didn't open, and discarding it made a
  failed migration and a corrupt file indistinguishable from a first run. The
  CloudKit tier failing is routine (no entitlement/account) and logs at
  `.notice`; the local-only tier failing is not (both point at the same file)
  and logs at `.error`.
- **Never tell the user to reinstall.** Falling back to in-memory means their
  entries are still on disk and usually recoverable by a fixed build — deleting
  the app is the one action that makes the loss permanent. `UserDefaultsKey
  .persistentStoreOpened` is latched the first time a persistent store opens, so
  `CadenceApp.hadPersistentStore` can tell "nothing saved here yet, reinstalling
  is harmless" from "your history is on this device, don't delete it"; the
  storage alert and `StorageFatalErrorView` word themselves off that. Both
  previously advised reinstalling while also saying the data was safe.
- **Removing a `@Model`'s stored property silently destroys its data.** There is
  no `SchemaMigrationPlan`, so SwiftData's implicit lightweight migration drops
  the column on first launch of the new build — nothing throws, and there is no
  hook at which the old values could be read first. This already cost real data
  once: moving the twelve `hk*` attributes off `DailyLog` was correct, but on a
  pre-split install every historical HealthKit value went with them (the JSON
  backup is the only manual route across that upgrade, and it restores health
  rows correctly now). `SchemaShapeTests` in `CadenceTests/SchemaMigrationTests
  .swift` pins every entity's exact attribute set so the next such change fails
  in CI instead of on a device; a new `@Model` needs a pin too. When a pin
  failure is intentional, decide what happens to the existing data **first**.
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
- **The push capability belongs to CloudKit — don't "clean it up".** Cadence
  ships no push feature and no `registerForRemoteNotifications` call, so the
  `aps-environment` entitlement (`Cadence/Cadence.entitlements`) and
  `UIBackgroundModes: remote-notification` (`Cadence/App/Info.plist`) both look
  unused from a grep of the Swift sources. They aren't:
  `NSPersistentCloudKitContainer` — which SwiftData's mirroring is built on, and
  which `CloudSyncMonitor` already observes directly — registers for remote
  notifications itself, and CloudKit announces "another device wrote something"
  with a silent push. Remove either key and remote changes stop importing until
  the next launch, with no error surfaced anywhere. This is the configuration
  Apple's Core Data + CloudKit setup prescribes, so it is an intended background
  use under Guideline 2.5.4, not a 2.5.4 risk. Both were dropped in `3786b68` on
  exactly that reasoning and restored afterwards; keep Push Notifications
  enabled on the App ID too, and note that HealthKit background delivery is a
  separate entitlement that needs neither key.

## Conventions

- **Logging:** `OSLog` — `Logger(subsystem: "com.carpecadence", category: "...")`.
- **Styling:** colors via `CadenceColor` (asset catalog), animations via
  `CadenceAnimation`, tunable thresholds in `Shared/Constants.swift`
  (`PatternThreshold`, etc.). Don't hardcode these inline.
- **Haptics:** `UINotificationFeedbackGenerator().notificationOccurred(...)` on
  successful saves.
- **File placement:** cross-cutting extensions go in
  `Shared/Extensions/Type+Extensions.swift` (`View+Extensions.swift`,
  `EnvironmentValues+Services.swift`) — don't add one inline in the first
  feature file that needs it. Reusable cross-feature UI goes in
  `Shared/Components/` (`MetricSlider.swift`, `AttachmentPhotoStrip.swift`,
  `AmbientMeshBackground.swift`); feature-local views stay in
  `Features/<Feature>/`.

## Code quality conventions

- **Concurrency mode: app, widget, and watch are Swift 6 language mode**
  (Xcode 27, iOS 27 SDK). Per-target settings, as they actually are in
  `project.pbxproj` (an earlier version of this section misstated them):

  | Target | `SWIFT_VERSION` | Approachable concurrency | Member import visibility | Other |
  |---|---|---|---|---|
  | Cadence (app) | 6.0 | — | — | |
  | CadenceWidgetExtension | 6.0 | YES | YES | |
  | CadenceWidget Watch App | 6.0 | YES | YES | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
  | CadenceTests | 5.9 | — | — | |
  | CadenceUITests | 5.0 | YES | YES | |

  Don't flip approachable concurrency on or off for a target as a "cleanup".
  It changes where every `nonisolated async` function runs (caller's actor vs.
  the global executor), which is a runtime behaviour change, not just a
  diagnostics one. The Swift 6 migration kept each target's setting exactly as
  it was for that reason.
- **Fix isolation errors by restructuring, not suppressing.** Make whatever
  crosses an isolation boundary genuinely `Sendable`. Examples from the
  migration: `HealthKitService`'s fetch helpers take `start`/`end` `Date`s and
  build their own `NSPredicate` instead of sharing one across `async let`
  tasks; WatchConnectivity payloads become `QuickLogPayload` before the
  main-actor hop. `nonisolated(unsafe)`, `@unchecked Sendable`, and
  `@preconcurrency` are only for an Apple API the SDK hasn't annotated or a
  state the compiler can't see is lock-guarded, and each one carries a comment
  naming the guarantee relied on. Current instances: the WCSession
  `replyHandler` in `PhoneConnectivityManager` and
  `CadenceApp._sharedModelContainer` behind `containerLock`. `@Model`
  `Sendable` conformance is still macro-synthesized rather than real, so the
  Snapshot boundary (see Architecture) still matters under Swift 6.
- **Pure helpers on a `View` or `@MainActor` type must be `nonisolated static`.**
  A member of a SwiftUI `View` is implicitly `@MainActor`. Swift 6 compiles
  **runtime** isolation checks into it (SE-0423), so a closure inside such a
  helper traps the moment it's called off the main thread. The Swift 5.9 test
  target calls helpers from nonisolated suites on background threads, and
  because `View`'s isolation is `@preconcurrency`, *no compiler diagnostic
  warns you*, not even with strict checking. The symptom is the crash-loop
  described under Testing. `HistoryView.logMatches` did exactly this, as would
  `TrendChartView.nearestPoint` and `.mean`; all three are
  `nonisolated static` now, following `HealthKitService`'s existing pure
  statics (`sleepQualityScore`, `isIntenseExercise`, …).
- **Never hold `@Model` instances in a `static`.** `SymptomTag.defaults` was a
  `static let` array of models. Seeding inserted those shared objects into a
  context, and `HealthKitService` then read them off the main actor. Static
  seed data is plain values (`SymptomTag.defaultSeeds`, the same shape as
  `optionalCatalog`), and models are built fresh where they're inserted
  (`makeDefaults()`).
- **Fire-and-forget `Task {}` vs. the cancelable pattern.** Bare `Task { }`
  with no stored handle is the default for best-effort `@MainActor` side
  effects that can silently fail or be superseded (HealthKit publish, widget
  republish, etc.) — most call sites use this. Reserve a stored `Task` handle
  + `Task.detached` + explicit `Task.isCancelled` checks + `MainActor.run`
  hop-back for long-running or user-cancelable work — see `LogInputFlow`'s
  `hkTask` and `ExportView`'s `generationTask`. Rule of thumb: if navigating
  away mid-operation would waste work or race the UI, use the heavy pattern;
  otherwise bare `Task {}` is correct, not a smell.
- **No force unwraps, `try!`, `as!`, `fatalError`, or `assert`.** Use
  `guard let`/`if let`/`??` instead, and the `Bool`-returning `save()` +
  `saveError` convention instead of throwing+`try!`. This is essentially a
  hard rule in this codebase already — hold new code to it.
- **`try?` is for read-only fetches only**, always defaulted:
  `(try? modelContext.fetch(...)) ?? []`. Never use `try?` to swallow a save
  failure — saves go through `save()`/`saveError`; silently dropping a save
  with `try?` would lose user data.
- **Three known unseamed singletons:** `StoreService.shared`,
  `CloudSyncMonitor.shared`, and `PhoneConnectivityManager` have no protocol
  seam, unlike the documented protocol trio (see "Services behind protocols"
  above). This is a deliberate, known gap — don't assume every `.shared`
  singleton is fake-injectable, and don't retrofit a protocol onto one of
  these three as unrequested cleanup.
- **Accessibility on custom controls.** Any hand-built interactive control
  (slider, chip, chart mark, non-standard `Button`) needs
  `.accessibilityElement` + `.accessibilityLabel` + `.accessibilityValue` +
  `.accessibilityHint` + traits — `SymptomPickerView`'s severity chip is the
  reference pattern to copy. Standard `Form`/`List`/`Button(label:)` rows get
  this for free and need nothing extra. Matters more than usual here since
  Cadence is a health app.

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
- **Undo for a quick check-in** is app-side, not `UndoableIntent`. Apple's docs
  say app intents never call `undo()` themselves ("Your app initiates undo and
  redo operations in response to interactions with its menus or interface"), and
  `undoManager` is nil when no suitable manager exists — the usual case when
  Siri launches the app in the background. Adopting the protocol would also pin
  `LogCheckInIntent` to iOS 26+, removing the Siri check-in for everyone below.
  Instead `applyQuickLog` records what the day looked like before it wrote
  (`QuickLogUndoRecord` in `UserDefaults`, local only, keyed by source so the row
  can name Siri / watch / widget), and the dashboard offers Undo under Today's
  Log. `QuickLogUndo.availableRecord` only offers it while the check-in is still
  the last word on today — once the day is edited by hand the offer retires
  itself rather than throwing away newer work. Undo deletes the log when the
  check-in created it, and the caller re-publishes to Health afterwards so the
  State of Mind entry goes with it.
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
  scale identical on both sides. On the phone, the nonisolated
  `WCSessionDelegate` callbacks parse the dictionary into `QuickLogPayload`
  (`Sendable`) *before* hopping to the main actor. `[String: Any]` can't cross
  that boundary under Swift 6. The parser does type extraction only (mood must
  be an `Int`; a non-`Int` energy is dropped, not fatal; a missing date means
  now), and clamping stays in the upsert. `applyQuickLog(_ payload: [String:
  Any], context:)` still exists as the entry point for the widget queue, the
  Siri intent, and `SeamTests`, and delegates to the typed overload, so there
  is one parser.
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
  `ChartThreshold`. `TrendChartView.mean`, `ChartMetric.isImprovement`,
  `ChartSeries.isImprovement`, and `InsightsView.workoutMinutes(for:from:)`
  are the pure, unit-tested helpers.
- **A dictionary-backed series must cover the comparison window too.**
  `ChartSeries.workoutMinutes` reads every value out of the `minutesByDay` map
  it is handed, so a day absent from that map is indistinguishable from a day
  with no workout. Building the map from the visible range alone therefore made
  the period-comparison badge impossible — `previousAverage` averages the
  series over `previousLogs`, which all resolved to nil. `InsightsView` now
  merges the previous window's days into the lookup map while still taking the
  chart's PRESENCE and y-domain from the visible range only, so an out-of-range
  workout still can't summon the chart or stretch its axis.
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
  writes the temp file). **Every export writes through
  `ExportScratch.write(_:to:)`** — never `Data.write(to:options:)` directly and
  never a renderer's own file-writing call. That seam applies `.atomic` +
  `.completeFileProtection`, without which a generated report stays readable off
  a locked device that has been unlocked once since boot. `PDFBuilder` used to
  call `UIGraphicsPDFRenderer.writePDF(to:)`, which takes a URL and no write
  options, so the full narrative report — the most sensitive of the three files
  — was the one export missing the protection the CSV and JSON backup had; it
  now renders via `pdfData` and hands the bytes to the seam. The protection
  class is **not assertable in tests** (the simulator reports `.protectionKey`
  as nil regardless), so the single code path is the guarantee.
  `AttachmentStore` deliberately stays outside this seam — media uses
  `.completeFileProtectionUnlessOpen` so a photo or voice note stays readable
  while it's on screen or playing. Both are driven from `ExportView`; PDFs open in
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
  **`HealthSnapshot` rows are the exception to that identity rule**, and must
  stay one: they restore for EVERY backed-up day regardless of whether that
  day's `DailyLog` already exists, and they merge per FIELD via
  `HealthSnapshot.backfill(from:)` (the row's own measurements win; the file
  only fills nils) rather than being skipped whole. The reason is the store
  split — `DailyLog` is CloudKit-mirrored and `HealthSnapshot` deliberately
  isn't, so on a new device the diary arrives on its own and the backup file is
  the *only* route back for the health half. Gating the health write on "the log
  was missing" — as the first version of this code did — made restore recover
  nothing in exactly that case. `RestoreSummary.restoredHealthDays` is counted
  and surfaced separately from `insertedTotal` for the same reason: "0 records,
  N health days" is the normal new-device outcome, and reporting only
  `insertedTotal` would announce that restore as a no-op.
- **Sync status**: `CloudSyncMonitor` (@MainActor singleton) folds
  `NSPersistentCloudKitContainer.eventChangedNotification` events (SwiftData's
  mirroring is built on that container) plus the CloudKit account status into
  one `SyncState`. `CadenceApp.usingCloudKitStore` records whether the
  CloudKit-backed store actually initialised (vs the local fallback) so the row
  reads "Off — local storage" truthfully. The state fold (`stateAfterEvent`) is
  pure and unit-tested; sync events outrank the account probe in both
  directions — the probe only moves `.waiting` to `.noAccount` on a missing
  account, and only moves `.noAccount` back to `.waiting` on a recovered one,
  never touching `.synced`/`.syncing`/`.error`. `apply(...)` is `internal`
  rather than `private`, and `coalesceInterval` is a settable
  `@ObservationIgnored var` rather than a constant, purely so
  `RemoteImportRefreshTests` (`coalescesBurst`, `exportDoesNotTriggerRefresh`)
  can construct a bare `CloudSyncMonitor()`, drop the interval to
  milliseconds, and call `apply` directly — driving the debounce without a
  real CloudKit notification or a real `SyncThreshold.remoteImportCoalesceSeconds`
  wait. Don't re-privatise either as cleanup; doing so breaks those tests.
  `CloudSyncMonitor.start()` runs at **launch** (in `CadenceApp`, beside
  `PhoneConnectivityManager.start`), not on first Settings visit as it once did:
  it now also drives the post-import refresh, so its observer needs to be
  registered before the earliest point an import could finish. That point is
  NOT "app launch" — `NSPersistentCloudKitContainer` begins mirroring when
  `sharedModelContainer`'s static initialiser first runs, which happens before
  SwiftUI's scene body ever evaluates, while the observer isn't installed until
  the `.task` that calls `start()` actually executes. An import that completes
  in that gap fires nothing; nothing currently closes it. `start()`'s observer
  registration is still idempotent (`if observer == nil`), so it installs at
  most once, but the account probe below it runs on **every** call, including
  `SyncBackupSection`'s own `.task { syncMonitor.start() }` — that used to be a
  harmless no-op once launch also called `start()` first, until it was made to
  re-probe: launch can happen signed out of iCloud (`.noAccount`), and without
  a re-probe on the Settings visit, signing in from Settings.app and returning
  left the row stuck reading "No iCloud account" for the rest of the session.
  A finished, successful **import** (`shouldReactTo`, pure and tested; exports
  are this device's own writes and setup moves no data) fires `onRemoteImport`,
  debounced by `SyncThreshold.remoteImportCoalesceSeconds` because CloudKit
  delivers a pass as a burst and `WidgetCenter` reloads are system-budgeted.
  `CadenceApp.applyRemoteImport` republishes the widget summary unconditionally
  (cheap: `publishWidgetSummary` already skips its own write/reload when the
  summary is unchanged) and clears `UserDefaultsKey.lastInsightCheckDay` so the
  next foreground recomputes insights — but only when the import's data
  observably changed. "The import finished successfully" is not, by itself,
  evidence of that: `NSPersistentCloudKitContainer` reports `succeeded == true`
  for a pass that imported nothing, including the import this device's own
  export echoes back as a push, and the `Event` carries no changed-record
  count for `shouldReactTo` to key off. `applyRemoteImport` instead compares a
  cheap fingerprint of the fetched logs (count, latest date, completed count,
  stored under `UserDefaultsKey.lastRemoteImportFingerprint`) against the
  previous one and only clears the throttle when it differs — otherwise a
  single-device Pro user would re-run the synchronous 90-day `PatternEngine`
  pass on every one of their own writes instead of once a day. The fingerprint
  is deliberately cheap, not exhaustive: an edit to an existing day that
  changes none of those three fields doesn't clear the throttle, and that
  insight surfaces on the next calendar day's regular check instead of
  immediately — an accepted trade, not a bug. It deliberately does **not**
  recompute inline: that would let a background import fire a health
  notification at an arbitrary hour.
  **SwiftData's `HistoryObserver` (iOS 27) was evaluated and rejected** for this
  — it is iOS 27-only against an iOS 17 floor (so the fallback would be the
  feature), its only output is an `eventCounter` bump carrying no more
  information than the CloudKit event already does, and it needs a live process,
  so it cannot help when the app isn't running. Don't reintroduce it.

## Week Reflection

- **On-device summary of the week** (`WeekReflectionService`, shown by
  `WeekReflectionCard` at the first weekly-review step, iOS 26+ Foundation
  Models). Everything below comes from evaluating the prompt against the iOS 27
  model (harness: `Tools/ReflectionEval`; baselines in the tmpfiles
  `reflection-eval/` folder).
- **Plain text, never `@Generable`.** Guided generation is blocked by the
  guardrail on weeks mentioning medications — 6 of 6 blocked, against 0 of 12
  for every plain-text combination of old/new instructions and prompt.
  Medications are a first-class feature, so guided generation is out. Formatting
  is stripped afterwards by `sanitize(_:)` instead, because the card renders the
  text verbatim and markdown would show as literal asterisks.
- **Only what the user entered reaches the model.** `promptText` gates mood on
  `didEditMood` and energy/sleep on `didEditMetrics`, the same flags
  `PatternEngine` and the Health write-back use, and drops a day with nothing
  filled in. Before that gate, a week whose note said "forgot to fill most of
  this in" was summarized as "a mood of 3/5, energy at 5/10, sleep at 7.0h" in 3
  of 3 runs — `DailyLog`'s defaults, reported as fact.
- **Direction of change is computed in Swift**, never inferred by the model:
  `trendVerb` turns first-vs-last into rose / dipped / eased / got stronger /
  held steady, and the prompt states it in words. Numeric series in the prompt
  get recited back into the summary (8.4 numbers per output when that was
  tried, against ~1.1 with verbs). Mood carries the app's own word
  ("mood 3/5 (neutral)") — without it the model called a 3 out of 5 "low".
- **The instructions are built per week** (`instructions(hasMood:dayCount:)`):
  the sentence range follows the day count, and the mood rule is omitted when no
  day recorded a mood, or the model invents one ("the mood was headache").
- **Prompt wording is localized and injected**, not read inline.
  `ReflectionStrings.current` reads the `reflection.*` catalog keys and the
  builder takes the value as a parameter, so tests build a Spanish prompt
  without changing the device language (`String(localized:locale:)` does not
  reliably select another language's strings). The card hides itself when
  `SystemLanguageModel.supportsLocale` is false for the app's language rather
  than answering in the wrong one. **The Spanish instructions must not contain a
  `("Tú…")` example** — the model copies it into its answer verbatim.
- **Crisis language skips the model entirely.** `CrisisLanguage.matches(in:)` is
  a fixed, accent-folded phrase list (English + Spanish) over the week's own
  notes; on a match `WeekReflectionCard` shows `SupportResourcesCard` — 988 in
  the US, Find A Helpline elsewhere (`CrisisSupport.resources(region:isSpanish:)`)
  — and never calls the model. It exists because the iOS 27 model summarized
  "had thoughts of hurting myself last night" back like any other entry, with no
  guardrail error and no refusal. It deliberately does **not** match general
  despair ("hopeless", "cried a lot"); those weeks still get a reflection, and
  the model handled them gently in every run. Helpline details were verified
  2026-09-15 against 988lifeline.org and findahelpline.com — re-verify when
  touching them, and don't claim a "press 2 for Spanish" phone option, which
  988's site does not document.
- **When Apple ships a new on-device model**, re-run `Tools/ReflectionEval`
  against the shipped service and compare with the archived baseline before
  changing any wording. Its README lists the acceptance thresholds.

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
  **A ternary of two bare literals is NOT the same trap** — this was documented
  backwards once and drove a whole pass of no-op rewrites. `Text(cond ? "a" :
  "b")`, `.accessibilityLabel(...)`, `.navigationTitle(...)` and
  `Label(cond ? "a" : "b", systemImage:)` all resolve to `LocalizedStringKey`
  and extract **both** branches (verified with `swiftc
  -emit-localized-strings`; `CustomTrackersView`'s "New Tracker"/"Edit Tracker"
  and `LogInputFlow`'s "Stop recording"/"Voice memo" exist in the catalog,
  translated, only because of ternary sites). It is a ternary of two
  `String`-*typed* values that silently skips the catalog — same as any other
  `String` variable. Splitting into two `Text`s is a fine style choice; it is
  not a localization fix.
- Not yet migrated: debug-only copy behind the simulated-data tooling in
  `SettingsView` (the `seedResultMessage` interpolations) — intentionally left.
- **Spanish (`es`) ships.** All catalog keys carry `es` translations
  (`knownRegions` includes `es`). When a new key appears in the catalog after
  a build, add its `es` value — an untranslated key silently falls back to
  English. Test with the scheme's App Language = Spanish, or
  `-AppleLanguages (es)`.
- **Permission sheet copy lives in `Cadence/App/InfoPlist.xcstrings`.** The
  `NS*UsageDescription` values in `Info.plist` are the base/English fallback;
  the catalog is what actually ships localized, and it carries `en` *and* `es`
  for all three (Health share, Health update, microphone). Change one and change
  the other — they are duplicated by design, the way Xcode's own workflow does
  it, and a mismatch means the Spanish sheet says something the English one
  doesn't. Verify after a build by reading `es.lproj/InfoPlist.strings` out of
  the built `.app`.
- **Known English-only surfaces** (plain `String` literals that never reach
  the catalog, each a deliberate follow-up, not an accident): `PDFBuilder`
  report copy, `PatternEngine` insight titles/details, `NotificationService`
  notification bodies, and the widget/watch targets (which would need their
  own `Localizable.xcstrings` in their synchronized folders).

## Testing

- **Swift Testing**, not XCTest: `import Testing`, `@Suite`, `@Test`, `#expect`,
  `#require`. Exception: **`CadenceUITests` is XCTest** (XCUIApplication has no
  Swift Testing equivalent). The smoke test launches with `--uitest`, which
  gives the app an in-memory store, fresh onboarding, and no permission
  prompts (`AppLaunch.isUITesting`) — keep new UI-affecting launch behavior
  behind that flag so UI runs stay deterministic.
- SwiftData tests use an **in-memory `ModelContainer`**, and every one of them
  passes a **unique configuration name**:
  `ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)`.
  This is not cosmetic. Unnamed in-memory configurations all resolve to the same
  store identity, so with Swift Testing running suites in parallel several
  containers end up sharing one store while declaring different schemas —
  inserting an entity the sharing container doesn't declare then throws
  `NSInvalidArgumentException: Can't assign an object to a store that does not
  contain the object's entity`, which is an **uncaught ObjC exception that kills
  the whole test bundle**. The symptom is maddening: every test passes when run
  alone, and the full run reports "0 tests" plus "Restarting after unexpected
  exit". Any new suite that builds a container must use a unique name too.
- **Every in-memory `ModelConfiguration` must pass `cloudKitDatabase: .none`.**
  It defaults to `.automatic`, so each test container tries to start CloudKit
  mirroring. With no iCloud account in a simulator the mirroring delegate fails
  setup, retries, and tears stores down mid-run, and a fetch in any other
  container in the process then throws `NSInternalInconsistencyException`
  ("No eligible connection available") — an uncaught ObjC exception that kills
  the bundle and is reported as every test failing. It is timing dependent: the
  same commit passed locally and in CI one day and failed on every local run the
  next, including with parallel execution disabled. The app's own test-path
  container passes `.none` for the same reason.
- **The unit-test host is a test launch too.** `AppLaunch.isRunningUnitTests`
  (set from `XCTestConfigurationFilePath`) exists because unit tests run inside
  the app: without it the host opened the real CloudKit-mirrored store while
  tests ran. Gate store selection on `AppLaunch.isTesting`, which covers both
  kinds of run; `isUITesting` alone still gates UI-affecting behaviour.
- Test containers should include **`HealthSnapshot.self`** whenever the code
  under test can reach a write path that upserts one (backup restore, the
  health refresher, the log-flow save). The exception is
  `SchemaMigrationTests.schema_containsExpectedModelTypes`, which asserts an
  exact `entities.count` and deliberately builds a narrow schema.
- Any suite that calls a `@MainActor` singleton (e.g. `NotificationService.shared`)
  must itself be annotated `@MainActor`, or it won't compile.
- **The same "0 tests / Restarting after unexpected exit" symptom has a second
  cause since Swift 6:** a nonisolated suite calling a main-actor-isolated
  helper that contains a closure. Swift 6's runtime isolation check traps inside
  it, the host process dies, and the retries take every suite down with it.
  The compiler gives no warning (see "Pure helpers on a `View` … must be
  `nonisolated static`" under Code quality conventions). To find the culprit,
  look at the newest `~/Library/Logs/DiagnosticReports/Cadence-*.ips`: the
  faulting thread shows `_dispatch_assert_queue_fail` →
  `swift_task_isCurrentExecutor…` → the helper and the test that called it.
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

## Web presence — IMPORTANT

- This repo is **public** and `docs/` is the live GitHub Pages root
  (Settings → Pages, source `main` / `/docs`, serving
  `jaguero21.github.io/Cadence`) — everything under `docs/` is publicly
  served, not just the four site pages. `docs/superpowers/` (this repo's
  spec/plan doc convention, per the `brainstorming`/`writing-plans`
  Claude Code skills) briefly leaked into this folder and got scrubbed from
  git history entirely (`git filter-repo`, force-pushed) on 2026-07-24 —
  don't reintroduce it.
- **Spec and plan docs for this repo do not go in `docs/`.** Write them to
  `/Volumes/APFS2/SwiftPorjects/tmpfiles/Cadence/docs-superpowers/{plans,specs}/`
  instead (outside the repo entirely, so there's nothing to accidentally
  commit or serve). `docs/superpowers/` is also listed in `.gitignore` as a
  belt-and-suspenders backstop, but the working convention is: never write
  there in the first place.
- Before adding any new file under `docs/`, ask whether it's meant to be
  public — `docs/` should contain only the site's HTML/CSS/JS and the two
  image assets (`app_icon.png`, `mascot.png`), nothing else.

## Build / test

- Build & run tests in Xcode with ⌘U (scheme `Cadence`, test plan
  `Cadence.xctestplan`).
- Some environments have only the Command Line Tools (no `xcodebuild`/`Xcode.app`);
  there you can edit but not compile. SourceKit then reports spurious
  "Cannot find type ..." / "SwiftDataMacros ... plugin not found" diagnostics
  for cross-file and macro references — treat those as indexer noise, not errors.
- **Xcode 27 is required** (Swift 6 language mode, iOS 27 SDK). Xcode 26.x can't
  build the project.
- **CI** (`.github/workflows/ci.yml`) runs on every push, on GitHub's
  `xcode-27` runner image (public preview as of 2026-09; `macos-latest` only
  has Xcode 26.6). It selects the newest installed `Xcode_27*.app` and fails
  loudly if there isn't one. It doesn't float to "newest Xcode", because Swift 6
  diagnostics change between compiler versions. It ensures a watchOS simulator
  runtime (the scheme embeds the watch app), picks an iPhone simulator, and
  runs `xcodebuild test -scheme Cadence -testPlan Cadence`. It then gates on
  `** TEST SUCCEEDED **`, on the Swift Testing count being at least
  `MIN_TESTS`, and on **zero compiler warnings in the app, widget, and watch
  targets** (`.github/scripts/check_warnings.py`, which re-points
  macro-expansion warnings to their source line and excludes the test
  targets). Run the same script locally against an `xcodebuild` log before
  pushing. There is no lint/format
  tooling in the repo (no `.swiftlint.yml`/`.swiftformat`/lint build phase) —
  style consistency is enforced only by the conventions in this file, not by
  a linter.
