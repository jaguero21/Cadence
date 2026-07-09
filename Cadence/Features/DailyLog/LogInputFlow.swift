import SwiftUI
import SwiftData
import PhotosUI
import OSLog

struct LogInputFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
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
    @State private var photoItem: PhotosPickerItem?
    @State private var audioRecorder = AudioRecorder()
    private let attachmentStore = AttachmentStore()
    @State private var peaksAndValleysNote: String = ""
    @State private var peaksAndValleysVoiceMemo: Attachment?
    @State private var peaksAndValleysRecorder = AudioRecorder()
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
                progressBar
                ScrollView {
                    VStack(spacing: 20) {
                        switch vm.currentStep {
                        case .mood:        moodStep
                        case .bodyMetrics: bodyMetricsStep
                        case .basics:      basicsStep
                        case .symptoms:    symptomStep
                        case .factors:     factorsStep
                        case .peaksAndValleys: peaksAndValleysStep
                        case .intentions:  intentionsStep
                        case .note:        noteStep
                        case .done:        doneStep
                        }
                    }
                    .padding()
                }
                .background(CadenceColor.background)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(vm.currentStep)
                .safeAreaInset(edge: .bottom) { navigationButtons }
            }
            .background(CadenceColor.background.ignoresSafeArea())
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
                    hydratedAttachmentIDs = Set(log.attachments.map(\.id) + [log.peaksAndValleysVoiceMemo?.id].compactMap { $0 })
                    peaksAndValleysNote     = log.peaksAndValleysNote
                    peaksAndValleysVoiceMemo = log.peaksAndValleysVoiceMemo
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
                if existingLog != nil || createdLog != nil || !attachments.isEmpty || peaksAndValleysVoiceMemo != nil {
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
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let steps = LogStep.allCases.filter { $0 != .done }
        let progress = Double(vm.currentStep.rawValue) / Double(steps.count)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemFill))
                    .frame(height: 3)
                Rectangle()
                    .fill(CadenceColor.accent)
                    .frame(width: geo.size.width * min(progress, 1), height: 3)
                    .animation(CadenceAnimation.smooth, value: vm.currentStep)
            }
        }
        .frame(height: 3)
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(moodEmoji(value))
                            .font(.system(size: 34))
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
        ("Hydration",        "drop"),
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : item.icon)
                                .foregroundStyle(selected ? CadenceColor.successGreen : .secondary)
                                .frame(width: 20)
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

    private static let factorItems: [(name: String, icon: String)] = [
        ("Alcohol",          "wineglass"),
        ("Caffeine",         "cup.and.saucer.fill"),
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : item.icon)
                                .foregroundStyle(selected ? CadenceColor.stressRed : .secondary)
                                .frame(width: 20)
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

            VoiceMemoRow(
                attachment: $peaksAndValleysVoiceMemo,
                recorder: peaksAndValleysRecorder,
                store: attachmentStore,
                onReplace: { old, _ in if let old { deleteVoiceMemoFile(old) } },
                onDelete: { deleteVoiceMemoFile($0) }
            )
        }
        .cadenceCard()
    }

    // Mirrors removeAttachment's hydrated-vs-session deletion bookkeeping: a
    // memo added this session can go immediately, but a persisted one keeps
    // its binary until the save that drops the reference succeeds.
    private func deleteVoiceMemoFile(_ attachment: Attachment) {
        if hydratedAttachmentIDs.contains(attachment.id) {
            pendingFileDeletions.append(attachment.filename)
        } else {
            attachmentStore.delete(attachment.filename)
        }
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

            photosSection
        }
        .cadenceCard()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
    }

    private var photosSection: some View {
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
                    Label(audioRecorder.isRecording ? "Stop recording" : "Voice note",
                          systemImage: audioRecorder.isRecording ? "stop.circle.fill" : "mic.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(audioRecorder.isRecording ? CadenceColor.stressRed : CadenceColor.accent)
                }
            }

            ForEach(attachments.filter { $0.kind == .audio }) { note in
                HStack(spacing: 10) {
                    AudioPlaybackButton(url: attachmentStore.url(for: note.filename))
                    Text("Voice note").font(.subheadline)
                    Spacer()
                    Button {
                        removeAttachment(note)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            let photos = attachments.filter { $0.kind == .photo }
            if !photos.isEmpty {
                AttachmentPhotoStrip(photos: photos, store: attachmentStore, tileSize: 64) { photo in
                    removeAttachment(photo)
                }
            }
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let filename = attachmentStore.save(data, fileExtension: "jpg") else { return }
        attachments.append(Attachment(kind: .photo, filename: filename))
        photoItem = nil
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            guard let url = audioRecorder.stop(),
                  let data = try? Data(contentsOf: url),
                  let filename = attachmentStore.save(data, fileExtension: "m4a") else { return }
            attachments.append(Attachment(kind: .audio, filename: filename))
            try? FileManager.default.removeItem(at: url)
        } else {
            Task {
                guard await audioRecorder.requestPermission() else { return }
                audioRecorder.start()
            }
        }
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
                .symbolEffect(.bounce, value: 1)

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
                    if vm.currentStep == .note {
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
                        Text(vm.currentStep == .note ? "Finish" : "Next")
                            .font(.body.bold())
                        if vm.currentStep != .note {
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
        .background(.bar)
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
        log.peaksAndValleysVoiceMemo = peaksAndValleysVoiceMemo
        log.intentionsForTomorrow   = intentionsForTomorrow
        log.freeNote        = freeNote
        log.didEditMetrics  = didEditMetrics
        if let snapshot = hkSnapshot {
            if let steps   = snapshot.steps          { log.hkSteps          = steps }
            if let hr      = snapshot.restingHR      { log.hkRestingHR      = hr }
            if let hrv     = snapshot.hrv            { log.hkHRV            = hrv }
            if let sleep   = snapshot.sleepHours     { log.hkSleepHours     = sleep }
            if let energy  = snapshot.activeEnergy   { log.hkActiveEnergy   = energy }
            if let mindful = snapshot.mindfulMinutes { log.hkMindfulMinutes = mindful }
            if let temp    = snapshot.wristTemperature { log.hkWristTemp    = temp }
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
            DashboardViewModel.publishWidgetSummary(logs: logs)
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

// MARK: - Subviews

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
                        if snapped != hours {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            hours = snapped
                        }
                    }
                ),
                in: 0...12,
                step: 0.5
            )
            .tint(CadenceColor.sleepPurple)
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
                        if rounded != value {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            value = rounded
                        }
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(Color(.systemGray3))
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
                        if rounded != value {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            value = rounded
                        }
                    }
                ),
                in: 0...10,
                step: 1
            )
            .tint(Color(.systemGray3))
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
