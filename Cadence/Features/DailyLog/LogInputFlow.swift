import SwiftUI
import SwiftData
import PhotosUI
import TipKit
import OSLog

struct LogInputFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm = DailyLogViewModel()
    @Query(sort: \CustomTracker.sortOrder) private var customTrackers: [CustomTracker]

    private let existingLog: DailyLog?

    // Plain defaults — hydrated from existingLog in .onAppear (see body).
    // Keeping @State init out of init() avoids the SwiftUI stale-state
    // anti-pattern where the initialiser value is only read once on first
    // insertion, silently ignoring any future parent changes.
    @State private var mood: Int = 3
    @State private var didEditMood = false
    @State private var didEditMetrics = false
    @State private var energy: Int = 5
    @State private var sleepHours: Double = 7.0
    @State private var painLevel: Int = 0
    @State private var brainFogLevel: Int = 0
    @State private var stressLevel: Int = 5
    @State private var sleepQuality: Int = 5
    @State private var selectedSymptoms: [SymptomEntry] = []
    @State private var basicsCompleted: [String] = []
    @State private var selectedFactors: [String] = []
    @State private var customValues: [UUID: Int] = [:]
    @State private var attachments: [Attachment] = []
    // Filenames of already-persisted attachments the user removed this session.
    // Their binaries are deleted only after a successful save, so a failed save
    // or force-quit can't leave the stored log pointing at a missing file.
    @State private var pendingFileDeletions: [String] = []
    // IDs of attachments that were already persisted when the flow opened —
    // used to tell "safe to delete from disk immediately" (added this session)
    // from "defer deletion until the save that drops the reference succeeds".
    @State private var hydratedAttachmentIDs: Set<UUID> = []
    private let attachmentStore = AttachmentStore()
    @State private var peaksAndValleysNote: String = ""
    @State private var intentionsForTomorrow: String = ""
    @State private var freeNote: String = ""
    @State private var hkSnapshot: HealthKitSnapshot?
    @State private var isHydrated = false
    @State private var createdLog: DailyLog?
    @State private var logPersisted = false
    @State private var hkTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.carpecadence", category: "LogInputFlow")

    init(existingLog: DailyLog?) {
        self.existingLog = existingLog
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.currentStep != .done {
                    stepIndicator
                }
                ScrollView {
                    VStack(spacing: 20) {
                        switch vm.currentStep {
                        case .mood:        moodStep
                        case .bodyMetrics: bodyMetricsStep
                        case .basics:      basicsStep
                        case .symptoms:    symptomStep
                        case .factors:     factorsStep
                        case .reflection:  reflectionStep
                        case .done:        doneStep
                        }
                    }
                    .padding()
                }
                .transition(.cadenceStepSlide(reduceMotion: reduceMotion))
                .id(vm.currentStep)
                .safeAreaInset(edge: .bottom) {
                    // No bar at all on the completion screen — an empty glass
                    // strip reads as a stray box.
                    if vm.currentStep != .done {
                        navigationButtons
                    }
                }
                // Declarative haptics: one tick per meaningful state change,
                // regardless of which control caused it (chip, button, jump).
                .sensoryFeedback(.impact(weight: .light), trigger: vm.currentStep)
                .sensoryFeedback(.impact(weight: .medium), trigger: mood)
                .sensoryFeedback(.impact(weight: .light), trigger: basicsCompleted)
                .sensoryFeedback(.impact(weight: .light), trigger: selectedFactors)
            }
            .navigationTitle(vm.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !isHydrated else { return }
                isHydrated = true
                if let log = existingLog {
                    mood             = log.mood
                    didEditMood      = log.didEditMood
                    didEditMetrics   = log.didEditMetrics
                    energy           = log.energy
                    sleepHours       = log.sleepHours
                    painLevel        = log.painLevel
                    brainFogLevel    = log.brainFogLevel
                    stressLevel      = log.stressLevel
                    sleepQuality     = log.sleepQuality
                    basicsCompleted  = log.basicsCompleted
                    selectedSymptoms = log.symptoms
                    selectedFactors  = log.factors
                    customValues     = Dictionary(log.customMetrics.map { ($0.trackerID, $0.value) }, uniquingKeysWith: { a, _ in a })
                    attachments      = log.attachments
                    // Migrate the legacy single-slot Peaks & Valleys memo into
                    // the sectioned pool; the next save clears the old field.
                    if let legacyMemo = log.peaksAndValleysVoiceMemo,
                       !attachments.contains(where: { $0.id == legacyMemo.id }) {
                        var memo = legacyMemo
                        memo.section = Attachment.peaksAndValleysSection
                        attachments.append(memo)
                    }
                    hydratedAttachmentIDs = Set(attachments.map(\.id))
                    peaksAndValleysNote     = log.peaksAndValleysNote
                    intentionsForTomorrow   = log.intentionsForTomorrow
                    freeNote         = log.freeNote
                } else {
                    hkTask = Task { await applyHealthKitData() }
                }
            }
            .onDisappear {
                hkTask?.cancel()
                // Safety net: persist progress on any dismissal (backgrounding,
                // swipe-away) but only when a log is already in progress, to
                // avoid phantom entries. Attachments count as progress — their
                // binaries are already on disk and would be orphaned otherwise.
                if existingLog != nil || createdLog != nil || !attachments.isEmpty {
                    partialSave()
                }
            }
            .alert("Couldn't Save", isPresented: .init(
                get: { vm.saveError != nil },
                set: { if !$0 { vm.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save & Close") {
                        partialSave()
                        if vm.saveError == nil { Task { @MainActor in dismiss() } }
                    }
                }
            }
        }
        // Paint the SHEET surface, not the content: on iOS 26 sheet content is
        // inset from the sheet edges, so a content .background leaves side
        // strips — presentationBackground is the layer that actually fills.
        .presentationBackground {
            if vm.currentStep == .done {
                AmbientMeshBackground()
            } else {
                CadenceColor.background
            }
        }
    }

    // MARK: - Step Indicator

    // Tappable replacement for the old anonymous progress bar: shows where you
    // are AND jumps straight to any step — editing one field of an existing
    // log used to mean walking every page with Next.
    private var stepIndicator: some View {
        let steps = LogStep.allCases.filter { $0 != .done }
        return HStack(spacing: 0) {
            ForEach(steps, id: \.self) { step in
                let isCurrent = step == vm.currentStep
                Button {
                    vm.goTo(step)
                    JumpStepsTip().invalidate(reason: .actionPerformed)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: step.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                isCurrent ? CadenceColor.accent : Color(.systemFill),
                                in: Circle()
                            )
                            .foregroundStyle(isCurrent ? .white : .secondary)
                        // A hairline under the current step anchors the eye
                        // without needing per-step labels at this size.
                        Capsule()
                            .fill(isCurrent ? CadenceColor.accent : .clear)
                            .frame(width: 18, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step.title)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                .accessibilityHint(isCurrent ? "Current step" : "Jump to this step")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassBarBackground()
        .popoverTip(JumpStepsTip())
    }

    // MARK: - Mood Step

    private var moodStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "face.smiling", title: "OVERALL MOOD", time: "~30 sec")
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        withAnimation(CadenceAnimation.spring) { mood = value }
                        didEditMood = true
                    } label: {
                        Text(moodEmoji(value))
                            .font(.system(size: 34))
                            // The chosen face leans in; scaleEffect doesn't
                            // affect layout, so the row never reflows.
                            .scaleEffect(mood == value ? 1.22 : 1.0)
                            .animation(CadenceAnimation.spring, value: mood)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                mood == value
                                    ? CadenceColor.accent.opacity(0.12)
                                    : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(mood == value ? CadenceColor.accent : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(moodLabel(value))
                    .accessibilityAddTraits(mood == value ? [.isSelected] : [])
                }
            }
        }
        .cadenceCard()
    }

    // Shared with the watch app (MoodScale is a member of both targets) so the
    // wrist and the phone always render the same face for the same value.
    private func moodEmoji(_ value: Int) -> String {
        MoodScale.emoji(for: value)
    }

    private func moodLabel(_ value: Int) -> String {
        switch value {
        case 1: return "Very sad, 1 of 5"
        case 2: return "Sad, 2 of 5"
        case 3: return "Neutral, 3 of 5"
        case 4: return "Happy, 4 of 5"
        case 5: return "Very happy, 5 of 5"
        default: return "Neutral"
        }
    }

    // MARK: - Body Metrics Step

    private var bodyMetricsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            LogSectionHeader(icon: "waveform.path.ecg", title: "BODY METRICS", time: "~60 sec")
            VStack(spacing: 16) {
                BodyMetricRow(label: "Energy",        value: $energy)
                Divider()
                SleepHoursRow(hours: $sleepHours)
                Divider()
                BodyMetricRow(label: "Sleep quality", value: $sleepQuality)
                Divider()
                BodyMetricRow(label: "Pain / ache",   value: $painLevel)
                Divider()
                BodyMetricRow(label: "Brain fog",     value: $brainFogLevel)
                Divider()
                BodyMetricRow(label: "Anxiety",       value: $stressLevel)
                ForEach(customTrackers) { tracker in
                    Divider()
                    CustomMetricRow(
                        label: tracker.name,
                        unit: tracker.unit,
                        range: tracker.range,
                        value: Binding(
                            get: { customValues[tracker.id] ?? tracker.midpoint },
                            set: { customValues[tracker.id] = $0; didEditMetrics = true }
                        )
                    )
                }
            }
        }
        .cadenceCard()
        .onChange(of: energy)        { _, _ in didEditMetrics = true }
        .onChange(of: sleepHours)    { _, _ in didEditMetrics = true }
        .onChange(of: sleepQuality)  { _, _ in didEditMetrics = true }
        .onChange(of: painLevel)     { _, _ in didEditMetrics = true }
        .onChange(of: brainFogLevel) { _, _ in didEditMetrics = true }
        .onChange(of: stressLevel)   { _, _ in didEditMetrics = true }
    }

    // MARK: - Basics Step

    private static let basicItems: [(name: String, icon: String)] = [
        ("Medications",      "pill.fill"),
        (hydrationBasicName, "drop"),
        ("Movement",         "figure.walk"),
        ("Ate well",         "fork.knife"),
        ("Rest / nap",       "moon.zzz.fill"),
        ("Self-care moment", "heart"),
    ]

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "checklist", title: "BASICS DONE TODAY", time: "~30 sec")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Self.basicItems, id: \.name) { item in
                    let selected = basicsCompleted.contains(item.name)
                    Button {
                        withAnimation(CadenceAnimation.spring) {
                            if selected {
                                basicsCompleted.removeAll { $0 == item.name }
                            } else {
                                basicsCompleted.append(item.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : item.icon)
                                .foregroundStyle(selected ? CadenceColor.successGreen : .secondary)
                                .frame(width: 20)
                                .contentTransition(.symbolEffect(.replace))
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(selected ? CadenceColor.successGreen : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            selected
                                ? CadenceColor.successGreen.opacity(0.1)
                                : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? CadenceColor.successGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
        .cadenceCard()
    }

    // MARK: - Factors Step

    // Shared with the HealthKit auto-tags in applyHealthKitData — one name, so
    // a factor tagged from Health and one tapped by hand are the same factor
    // to PatternEngine and the reports.
    static let menstrualCycleFactorName = "Menstrual cycle"
    static let intenseExerciseFactorName = "Intense exercise"
    static let caffeineFactorName = "Caffeine"
    static let hydrationBasicName = "Hydration"

    private static let factorItems: [(name: String, icon: String)] = [
        ("Alcohol",          "wineglass"),
        (caffeineFactorName, "cup.and.saucer.fill"),
        ("Skipped meal",     "takeoutbag.and.cup.and.straw"),
        (intenseExerciseFactorName, "figure.run"),
        ("Travel",           "airplane"),
        ("Stressful event",  "exclamationmark.bubble"),
        ("Poor sleep",       "bed.double"),
        ("Late screen time", "iphone"),
        ("Weather change",   "cloud.sun"),
        (menstrualCycleFactorName, "drop.fill"),
    ]

    private var factorsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "exclamationmark.triangle", title: "POSSIBLE TRIGGERS", time: "~30 sec")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Self.factorItems, id: \.name) { item in
                    let selected = selectedFactors.contains(item.name)
                    Button {
                        withAnimation(CadenceAnimation.spring) {
                            if selected {
                                selectedFactors.removeAll { $0 == item.name }
                            } else {
                                selectedFactors.append(item.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : item.icon)
                                .foregroundStyle(selected ? CadenceColor.stressRed : .secondary)
                                .frame(width: 20)
                                .contentTransition(.symbolEffect(.replace))
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(selected ? CadenceColor.stressRed : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            selected
                                ? CadenceColor.stressRed.opacity(0.1)
                                : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? CadenceColor.stressRed.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
        .cadenceCard()
    }

    // MARK: - Symptoms Step

    private var symptomStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "bandage", title: "SYMPTOMS TODAY", time: "~30 sec")
            SymptomPickerView(selectedSymptoms: $selectedSymptoms)
        }
        .cadenceCard()
    }

    // MARK: - Reflection Step

    // The three closing reflections as one scrollable page of cards — the
    // fields stay independent (separate model fields, separate report
    // sections); only the pagination merged.
    private var reflectionStep: some View {
        VStack(spacing: 20) {
            peaksAndValleysStep
            intentionsStep
            noteStep
        }
    }

    // MARK: - Peaks & Valleys Step

    private var peaksAndValleysStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "arrow.up.arrow.down.circle", title: "PEAKS AND VALLEYS", time: "~60 sec")
            Text("What were the peaks and valleys of your day?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(
                "The best and hardest parts of today…",
                text: $peaksAndValleysNote,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(12)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))

            AttachmentControls(
                attachments: $attachments,
                section: Attachment.peaksAndValleysSection,
                store: attachmentStore,
                onRemove: removeAttachment
            )
        }
        .cadenceCard()
    }

    // MARK: - Intentions Step

    private var intentionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "sunrise.fill", title: "INTENTIONS FOR TOMORROW", time: "~30 sec")
            Text("Write your intentions for tomorrow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(
                "What do you want to carry into tomorrow?",
                text: $intentionsForTomorrow,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(12)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))

            AttachmentControls(
                attachments: $attachments,
                section: Attachment.intentionsSection,
                store: attachmentStore,
                onRemove: removeAttachment
            )
        }
        .cadenceCard()
    }

    // MARK: - Note Step

    private var noteStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "pencil", title: "ONE-LINE NOTE", time: "~60 sec")
            TextField(
                "One thing that stood out today — a symptom, a win, or just how it felt…",
                text: $freeNote,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(12)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))

            AttachmentControls(
                attachments: $attachments,
                section: nil,
                store: attachmentStore,
                onRemove: removeAttachment
            )
        }
        .cadenceCard()
    }

    private func removeAttachment(_ attachment: Attachment) {
        // An attachment added this session was never persisted — its file can
        // go immediately. A persisted one keeps its binary until the save that
        // drops the reference succeeds; deleting first would leave the stored
        // log pointing at a missing file if the save fails or never happens.
        if hydratedAttachmentIDs.contains(attachment.id) {
            pendingFileDeletions.append(attachment.filename)
        } else {
            attachmentStore.delete(attachment.filename)
        }
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Done Step

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(CadenceColor.successGreen)
                .cadenceSymbolBounce(value: 1)

            VStack(spacing: 8) {
                Text("Log complete!")
                    .font(.title.bold())
                Text("Your data is saved and will feed into your weekly insights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 24) {
                summaryPill(label: "Mood",   value: moodEmoji(mood),      color: CadenceColor.moodBlue)
                summaryPill(label: "Energy", value: "\(energy)/10",        color: CadenceColor.energyOrange)
                summaryPill(label: "Sleep",  value: "\(sleepQuality)/10",  color: CadenceColor.sleepPurple)
            }

            Button("Close") { Task { @MainActor in dismiss() } }
                .buttonStyle(.borderedProminent)
                .tint(CadenceColor.successGreen)
        }
        .padding(.top, 32)
    }

    private func summaryPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if vm.currentStep.rawValue > 0 && vm.currentStep != .done {
                Button {
                    vm.previousStep()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .frame(width: 44, height: 44)
                        .background(CadenceColor.cardBG, in: Circle())
                }
            }

            Spacer()

            if vm.currentStep != .done {
                Button {
                    if vm.currentStep == .reflection {
                        let log = ensureLog()
                        apply(to: log)
                        if existingLog == nil { modelContext.insert(log) }
                        guard vm.save(log: log, context: modelContext, notifications: notificationService) else {
                            if existingLog == nil, !logPersisted {
                                modelContext.delete(log)
                                createdLog = nil
                            }
                            return
                        }
                        logPersisted = true
                        publishToHealth(log)
                    }
                    vm.nextStep()
                } label: {
                    HStack {
                        Text(vm.currentStep == .reflection ? "Finish" : "Next")
                            .font(.body.bold())
                        if vm.currentStep != .reflection {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(CadenceColor.accent, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    // Returns the log for this flow — either the one we're editing, or a new
    // one we create and insert exactly once. Idempotent: repeated calls reuse
    // the same instance so save-retries don't violate the unique-date constraint.
    private func ensureLog() -> DailyLog {
        if let existing = existingLog { return existing }
        if let created = createdLog { return created }
        // existingLog was captured when the sheet opened; with no DB-level
        // unique constraint (CloudKit), today's log may have been created since
        // (watch quick-log, CloudKit import). Re-fetch at save time and adopt
        // it rather than inserting a same-date duplicate.
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == today })
        if let concurrent = try? modelContext.fetch(descriptor).first {
            createdLog = concurrent
            logPersisted = true   // already in the store — never rollback-delete it
            return concurrent
        }
        let newLog = DailyLog()
        createdLog = newLog
        return newLog
    }

    // Copies the current step-machine state onto the given log. No insertion;
    // call ensureLog() first.
    private func apply(to log: DailyLog) {
        log.mood            = mood.clamped(to: 1...5)
        log.didEditMood     = didEditMood
        log.energy          = energy.clamped(to: 0...10)
        log.sleepHours      = sleepHours
        log.painLevel       = painLevel.clamped(to: 0...10)
        log.brainFogLevel   = brainFogLevel.clamped(to: 0...10)
        log.stressLevel     = stressLevel.clamped(to: 0...10)
        log.sleepQuality    = sleepQuality.clamped(to: 0...10)
        log.basicsCompleted = basicsCompleted
        log.symptoms        = selectedSymptoms
        log.factors         = selectedFactors
        log.customMetrics   = customValues.map { MetricEntry(trackerID: $0.key, value: $0.value) }
        log.attachments     = attachments
        log.peaksAndValleysNote     = peaksAndValleysNote
        // Legacy single-slot memo was merged into `attachments` on hydrate
        // (section-tagged); clearing the field completes the migration.
        log.peaksAndValleysVoiceMemo = nil
        log.intentionsForTomorrow   = intentionsForTomorrow
        log.freeNote        = freeNote
        log.didEditMetrics  = didEditMetrics
        if let snapshot = hkSnapshot {
            log.applyObjectiveHealthData(snapshot)
        }
    }

    @MainActor
    private func applyHealthKitData() async {
        let service = healthKitService
        let snapshot = await withTaskGroup(of: HealthKitSnapshot?.self) { group in
            group.addTask { await service.fetchLogSnapshot() }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            defer { group.cancelAll() }
            for await result in group {
                return result  // first completer wins; nil means timeout fired
            }
            return nil
        }
        guard let snapshot, !Task.isCancelled else { return }
        hkSnapshot = snapshot
        // Pre-fill the Body Metrics sleep sliders from last night's measured
        // sleep — but never over a value the user already set. Hours snap to
        // the slider's half-hour steps; quality only arrives when the night
        // has real stage data (see HealthKitService.sleepQualityScore).
        if !didEditMetrics {
            if let sleep = snapshot.sleepHours {
                sleepHours = min(max((sleep * 2).rounded() / 2, 0), 12)
            }
            if let quality = snapshot.sleepQuality {
                sleepQuality = quality
            }
        }
        // Health has a cycle entry for today → pre-select the factor chip the
        // user would otherwise tap by hand. Just a pre-selection: the chip
        // stays fully manual (toggle it off, or on without Health at all).
        if snapshot.menstrualFlow == true, !selectedFactors.contains(Self.menstrualCycleFactorName) {
            selectedFactors.append(Self.menstrualCycleFactorName)
        }
        // Same for a day whose workouts clear the intensity gate.
        if snapshot.intenseWorkout == true, !selectedFactors.contains(Self.intenseExerciseFactorName) {
            selectedFactors.append(Self.intenseExerciseFactorName)
        }
        // Dietary entries logged in Health: enough caffeine selects the factor,
        // enough water checks the Hydration basic. Both stay fully manual.
        if let caffeine = snapshot.caffeineMilligrams, caffeine >= HealthThreshold.caffeineMilligrams,
           !selectedFactors.contains(Self.caffeineFactorName) {
            selectedFactors.append(Self.caffeineFactorName)
        }
        if let water = snapshot.waterLiters, water >= HealthThreshold.hydrationLiters,
           !basicsCompleted.contains(Self.hydrationBasicName) {
            basicsCompleted.append(Self.hydrationBasicName)
        }
        // Symptoms another app already logged in Health today prefill the
        // picker — only while the user hasn't chosen any themselves.
        if selectedSymptoms.isEmpty, !snapshot.symptoms.isEmpty {
            selectedSymptoms = snapshot.symptoms
        }
        // A daily mood logged elsewhere (State of Mind) prefills the mood step;
        // the user's own tap always wins.
        if !didEditMood, let externalMood = snapshot.mood {
            mood = externalMood
        }
    }

    // Fire-and-forget mirror of the saved day into Health (mapped symptoms +
    // State of Mind mood). Snapshot on the main actor; the write is
    // best-effort and can never block or fail the save it follows.
    private func publishToHealth(_ log: DailyLog) {
        let snapshot = DailyLogSnapshot(log)
        let service = healthKitService
        Task { await service.publish(log: snapshot) }
    }

    private func partialSave() {
        let log = ensureLog()
        apply(to: log)
        if existingLog == nil { modelContext.insert(log) }
        do {
            try modelContext.save()
            logPersisted = true
            // The save dropped the references to removed persisted attachments;
            // now their binaries can safely go.
            pendingFileDeletions.forEach(attachmentStore.delete)
            pendingFileDeletions.removeAll()
            // Keep the home-screen widget current without requiring a visit to
            // the Dashboard tab.
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            let flares = (try? modelContext.fetch(FetchDescriptor<Flare>())) ?? []
            DashboardViewModel.publishWidgetSummary(logs: logs, flares: flares)
            publishToHealth(log)
        } catch {
            Self.log.error("Partial save failed: \(error, privacy: .public)")
            if existingLog == nil, !logPersisted {
                modelContext.delete(log)
                createdLog = nil
            }
            vm.saveError = String(localized: "Your progress couldn't be saved. Please try again.")
        }
    }
}

// One-time discoverability for the step bar (TipKit handles show-once
// persistence; invalidated the first time the user actually jumps).
private struct JumpStepsTip: Tip {
    var title: Text { Text("Jump to any step") }
    var message: Text? { Text("Tap an icon to go straight to that part of the log.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
}

// MARK: - Subviews

// One attachment row per reflection card: add a photo or record a voice memo,
// with that card's own attachments listed beneath. Each instance owns its
// recorder and picker state; the `section` tag keeps the cards' pools separate
// while everything persists in the one DailyLog.attachments array (nil =
// the general one-line-note card, which also shows pre-tagging attachments).
private struct AttachmentControls: View {
    @Binding var attachments: [Attachment]
    let section: String?
    let store: AttachmentStore
    let onRemove: (Attachment) -> Void

    @State private var recorder = AudioRecorder()
    @State private var photoItem: PhotosPickerItem?

    private var sectionAttachments: [Attachment] {
        attachments.filter { $0.section == section }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Add photo", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(CadenceColor.accent)
                }
                Button {
                    toggleRecording()
                } label: {
                    Label(recorder.isRecording ? "Stop recording" : "Voice memo",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(recorder.isRecording ? CadenceColor.stressRed : CadenceColor.accent)
                }
            }

            ForEach(sectionAttachments.filter { $0.kind == .audio }) { memo in
                HStack(spacing: 10) {
                    AudioPlaybackButton(url: store.url(for: memo.filename))
                    Text("Voice memo").font(.subheadline)
                    Spacer()
                    Button {
                        onRemove(memo)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            let photos = sectionAttachments.filter { $0.kind == .photo }
            if !photos.isEmpty {
                AttachmentPhotoStrip(photos: photos, store: store, tileSize: 64) { photo in
                    onRemove(photo)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let filename = store.save(data, fileExtension: "jpg") else { return }
        attachments.append(Attachment(kind: .photo, filename: filename, section: section))
        photoItem = nil
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let url = recorder.stop(),
                  let data = try? Data(contentsOf: url),
                  let filename = store.save(data, fileExtension: "m4a") else { return }
            attachments.append(Attachment(kind: .audio, filename: filename, section: section))
            try? FileManager.default.removeItem(at: url)
        } else {
            Task {
                guard await recorder.requestPermission() else { return }
                recorder.start()
            }
        }
    }
}

private struct LogSectionHeader: View {
    let icon: String
    let title: String
    let time: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.systemFill), in: Capsule())
        }
    }
}

private struct SleepHoursRow: View {
    @Binding var hours: Double

    var body: some View {
        HStack(spacing: 14) {
            Text("Sleep hours")
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(
                    get: { hours },
                    set: { newVal in
                        let snapped = (newVal * 2).rounded() / 2
                        if snapped != hours { hours = snapped }
                    }
                ),
                in: 0...12,
                step: 0.5
            )
            .tint(CadenceColor.sleepPurple)
            .sensoryFeedback(.impact(weight: .light), trigger: hours)
            .accessibilityLabel("Sleep hours")
            .accessibilityValue(String(format: "%.1f hours", hours))
            Text(String(format: "%.1f", hours))
                .font(.headline.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(CadenceAnimation.smooth, value: hours)
        }
    }
}

private struct CustomMetricRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
                .lineLimit(2)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        let rounded = Int(newVal.rounded())
                        if rounded != value { value = rounded }
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(Color(.systemGray3))
            .sensoryFeedback(.impact(weight: .light), trigger: value)
            .accessibilityLabel(label)
            .accessibilityValue(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(CadenceAnimation.smooth, value: value)
        }
    }
}

private struct BodyMetricRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        let rounded = Int(newVal.rounded())
                        if rounded != value { value = rounded }
                    }
                ),
                in: 0...10,
                step: 1
            )
            .tint(Color(.systemGray3))
            .sensoryFeedback(.impact(weight: .light), trigger: value)
            .accessibilityLabel(label)
            .accessibilityValue("\(value) out of 10")
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(CadenceAnimation.smooth, value: value)
        }
    }
}
