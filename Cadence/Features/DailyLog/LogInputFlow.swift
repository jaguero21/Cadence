import SwiftUI
import SwiftData

struct LogInputFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
    @State private var vm = DailyLogViewModel()

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
    @State private var freeNote: String = ""
    @State private var hkSnapshot: HealthKitSnapshot?
    @State private var isHydrated = false
    @State private var createdLog: DailyLog?

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
                    freeNote         = log.freeNote
                } else {
                    Task { await applyHealthKitData() }
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

    private func moodEmoji(_ value: Int) -> String {
        switch value {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
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

    // MARK: - Symptoms Step

    private var symptomStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogSectionHeader(icon: "bandage", title: "SYMPTOMS TODAY", time: "~30 sec")
            SymptomPickerView(selectedSymptoms: $selectedSymptoms)
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
        }
        .cadenceCard()
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
                        guard vm.save(log: log, context: modelContext, notifications: notificationService) else { return }
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
        let newLog = DailyLog()
        modelContext.insert(newLog)
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
        log.freeNote        = freeNote
        log.didEditMetrics  = didEditMetrics
        if let snapshot = hkSnapshot {
            if let steps = snapshot.steps      { log.hkSteps     = steps }
            if let hr    = snapshot.restingHR  { log.hkRestingHR = hr }
            if let hrv   = snapshot.hrv        { log.hkHRV       = hrv }
            if let sleep = snapshot.sleepHours { log.hkSleepHours = sleep }
        }
    }

    @MainActor
    private func applyHealthKitData() async {
        let snapshot = await healthKitService.fetchLogSnapshot()
        hkSnapshot = snapshot
        // Pre-fill sleep slider only if the user hasn't touched metrics yet.
        if !didEditMetrics, let sleep = snapshot.sleepHours {
            sleepHours = sleep
        }
    }

    private func partialSave() {
        apply(to: ensureLog())
        do {
            try modelContext.save()
        } catch {
            vm.saveError = "Your progress couldn't be saved. Please try again."
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
