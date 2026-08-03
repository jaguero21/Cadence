import SwiftUI
import SwiftData
#if DEBUG
import OSLog
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreService.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.notificationService) private var notificationService
    @AppStorage(UserDefaultsKey.dailyReminderHour)    private var dailyHour: Int = 20
    @AppStorage(UserDefaultsKey.dailyReminderMinute)  private var dailyMinute: Int = 0
    @AppStorage(UserDefaultsKey.weeklyReminderEnabled) private var weeklyEnabled: Bool = true

    #if DEBUG
    @Query private var existingLogs: [DailyLog]
    @State private var seedResultMessage: String?
    @State private var showingSeedResult = false
    @State private var pdfShareURL: URL?
    @State private var showingPDFShare = false
    @State private var isGeneratingPDF = false
    private static let debugLog = Logger(subsystem: "com.carpecadence", category: "DebugSeed")
    #endif

    var body: some View {
        NavigationStack {
            List {
                proSection
                remindersSection
                medicationsSection
                flaresSection
                symptomsSection
                customTrackersSection
                healthKitSection
                SyncBackupSection()
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            #if DEBUG
            .alert("Seed Result", isPresented: $showingSeedResult) {
                Button("OK", role: .cancel) { seedResultMessage = nil }
            } message: {
                Text(seedResultMessage ?? "")
            }
            .sheet(isPresented: $showingPDFShare) {
                if let url = pdfShareURL {
                    ShareSheet(items: [url])
                }
            }
            #endif
        }
        .task { await store.loadProducts() }
        .task { appState.notificationsAuthorized = await notificationService.checkAuthorizationStatus() }
        .task { appState.healthKitAuthorized = healthKitService.isAuthorized }
    }

    // MARK: - Sections

    private var proSection: some View {
        Section {
            if store.isPro {
                HStack {
                    Label("Cadence Pro", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                    Spacer()
                    Text("Active").foregroundStyle(CadenceColor.successGreen)
                }
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export Report", systemImage: "doc.richtext.fill")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upgrade to Pro").font(.headline)
                    Text("Unlock full history, PDF export, pattern insights, custom symptoms, and HealthKit sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let product = store.lifetimeProduct {
                        Button("Buy Once — \(product.displayPrice)") {
                            Task { try? await store.purchase(product) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CadenceColor.sleepPurple)
                    }

                    Button("Restore Purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .font(.caption)
                    .foregroundStyle(CadenceColor.accent)
                }
            }
        } header: {
            Label("Subscription", systemImage: "crown.fill")
        }
    }

    private var remindersSection: some View {
        Section {
            DatePicker("Daily check-in time",
                selection: Binding(
                    get: {
                        var c = DateComponents(); c.hour = dailyHour; c.minute = dailyMinute
                        return Calendar.current.date(from: c) ?? .now
                    },
                    set: {
                        dailyHour = Calendar.current.component(.hour, from: $0)
                        dailyMinute = Calendar.current.component(.minute, from: $0)
                        notificationService.scheduleDailyReminder(at: dailyHour, minute: dailyMinute)
                    }
                ),
                displayedComponents: .hourAndMinute
            )

            Toggle("Weekly review reminder (Sundays 7pm)", isOn: $weeklyEnabled)
                .onChange(of: weeklyEnabled) { _, on in
                    if on { notificationService.scheduleWeeklyReviewReminder() }
                    else  { notificationService.removeNotification(id: NotificationID.weeklyReview) }
                }
        } header: {
            Label("Reminders", systemImage: "bell.fill")
        } footer: {
            if appState.notificationsAuthorized {
                Label("Notifications are enabled.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CadenceColor.successGreen)
            } else {
                HStack(spacing: 4) {
                    Label("Notifications are disabled.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(CadenceColor.stressRed)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            }
        }
    }

    private var symptomsSection: some View {
        Section {
            NavigationLink {
                SymptomLibraryView()
            } label: {
                Label("Symptoms", systemImage: "tag.fill")
            }
        } header: {
            Label("Symptoms", systemImage: "tag.fill")
        } footer: {
            Text("Choose which symptoms appear in the daily log's picker — the full library is free; custom ones require Pro.")
        }
    }

    private var medicationsSection: some View {
        Section {
            NavigationLink {
                MedicationsView()
            } label: {
                Label("Medications", systemImage: "pills.fill")
            }
        } header: {
            Label("Medications", systemImage: "pills.fill")
        } footer: {
            Text("Track what you take so Cadence can correlate it with your symptoms.")
        }
    }

    private var customTrackersSection: some View {
        Section {
            NavigationLink {
                CustomTrackersView()
            } label: {
                Label("Custom Trackers", systemImage: "slider.horizontal.3")
            }
        } footer: {
            Text("Define your own metrics to log alongside the built-in ones.")
        }
    }

    private var flaresSection: some View {
        Section {
            NavigationLink {
                FlaresView()
            } label: {
                Label("Flares", systemImage: "flame.fill")
            }
        } footer: {
            Text("Log multi-day symptom flares to track their frequency and duration.")
        }
    }

    private var healthKitSection: some View {
        Section {
            Button("Re-authorize HealthKit") {
                Task {
                    appState.healthKitAuthorized = (try? await healthKitService.requestAuthorization()) ?? healthKitService.isAuthorized
                }
            }
            .foregroundStyle(CadenceColor.accent)
        } header: {
            Label("HealthKit", systemImage: "heart.fill")
        } footer: {
            if !healthKitService.isAvailable {
                Text("HealthKit is not available on this device.")
            } else if appState.healthKitAuthorized {
                Label("HealthKit access granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CadenceColor.successGreen)
            } else {
                // Health permissions live in the Health app (Profile → Apps),
                // NOT on the app's page in Settings — openSettingsURLString
                // would land the user somewhere with no HealthKit row at all.
                VStack(alignment: .leading, spacing: 4) {
                    Label("Some HealthKit access is off.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(CadenceColor.stressRed)
                    HStack(spacing: 4) {
                        Text("Manage it in the Health app under Profile → Apps → Cadence.")
                        if let url = URL(string: "x-apple-health://") {
                            Link("Open Health", destination: url)
                        }
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            if let privacyURL = URL(string: "https://jaguero21.github.io/Cadence/privacy-policy.html") {
                Link("Privacy Policy", destination: privacyURL)
            }
            if let termsURL = URL(string: "https://jaguero21.github.io/Cadence/eula.html") {
                Link("Terms of Service", destination: termsURL)
            }
            if let learnMoreURL = URL(string: "https://jaguero21.github.io/Cadence/") {
                Link("Learn More About Cadence", destination: learnMoreURL)
            }
        }
    }

    #if DEBUG

    // MARK: - Debug

    private var debugSection: some View {
        Section {
            Button("Seed 7 days of sample data") {
                seedDays(Self.sampleDays)
            }
            .foregroundStyle(CadenceColor.accent)

            Button("Seed 30 more days (deeper history)") {
                seedDays(Self.extendedSampleDays)
            }
            .foregroundStyle(CadenceColor.accent)

            Button("Seed 90 more days (a full quarter)") {
                seedDays(Self.quarterSampleDays)
            }
            .foregroundStyle(CadenceColor.accent)

            Button {
                Task { await generateDoctorPDF(daysBack: 30) }
            } label: {
                HStack {
                    Text("Generate 30 Day Trends report")
                    Spacer()
                    if isGeneratingPDF { ProgressView() }
                }
            }
            .disabled(isGeneratingPDF)
            .foregroundStyle(CadenceColor.accent)

            Button {
                Task { await generateDoctorPDF(daysBack: 90) }
            } label: {
                HStack {
                    Text("Generate 90 Day Trends report")
                    Spacer()
                    if isGeneratingPDF { ProgressView() }
                }
            }
            .disabled(isGeneratingPDF)
            .foregroundStyle(CadenceColor.accent)
        } header: {
            Label("Debug", systemImage: "hammer.fill")
        } footer: {
            Text("Seed actions skip dates that already have a log, so they're additive. PDF actions build a doctor report from the last N days of logs (whatever is in the store) and open the share sheet — bypasses the Pro gate in DEBUG.")
        }
    }

    private func generateDoctorPDF(daysBack: Int) async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -daysBack, to: .now) ?? .now
        let snapshots = existingLogs
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
            .map(DailyLogSnapshot.init)
        let url = await PDFBuilder.build(logs: snapshots, reviews: [])
        if let url {
            pdfShareURL = url
            showingPDFShare = true
        } else {
            seedResultMessage = "PDF generation failed."
            showingSeedResult = true
        }
    }

    private func seedDays(_ days: [SampleDay]) {
        let cal = Calendar.current
        let existingDates = Set(existingLogs.map { cal.startOfDay(for: $0.date) })
        var inserted = 0
        var skipped = 0
        for day in days {
            guard let date = cal.date(byAdding: .day, value: -day.daysAgo, to: .now) else { continue }
            let dayStart = cal.startOfDay(for: date)
            if existingDates.contains(dayStart) { skipped += 1; continue }
            let log = DailyLog(date: dayStart)
            log.mood            = day.mood
            log.didEditMood     = true
            log.energy          = day.energy
            log.sleepHours      = day.sleepHours
            log.sleepQuality    = day.sleepQuality
            log.stressLevel     = day.stressLevel
            log.painLevel       = day.painLevel
            log.brainFogLevel   = day.brainFogLevel
            log.symptoms        = day.symptoms
            log.basicsCompleted = day.basicsCompleted
            log.freeNote        = day.freeNote
            log.didEditMetrics  = true
            log.isComplete      = true
            modelContext.insert(log)
            inserted += 1
        }
        do {
            try modelContext.save()
            seedResultMessage = "Inserted \(inserted) day(s)" + (skipped > 0 ? ", skipped \(skipped) existing." : ".")
        } catch {
            Self.debugLog.error("Failed to save sample data: \(error, privacy: .public)")
            seedResultMessage = "Save failed: \(error.localizedDescription)"
        }
        showingSeedResult = true
    }

    private struct SampleDay {
        let daysAgo: Int
        let mood: Int
        let energy: Int
        let sleepHours: Double
        let stressLevel: Int
        let sleepQuality: Int
        let painLevel: Int
        let brainFogLevel: Int
        let symptoms: [SymptomEntry]
        let basicsCompleted: [String]
        let freeNote: String
    }

    // Curated 7-day arc: stressful start (days -7…-5 high stress + poor sleep),
    // recovery on day -4 (fatigue spike), gradually better by day -1.
    // Designed so sleep-headache correlation and mood-sleep correlation both fire.
    private static let sampleDays: [SampleDay] = [
        SampleDay(daysAgo: 7, mood: 2, energy: 3, sleepHours: 5.0, stressLevel: 8, sleepQuality: 3, painLevel: 2, brainFogLevel: 4,
                  symptoms: [],
                  basicsCompleted: ["Medications", "Hydration"],
                  freeNote: "Deadline crunch — barely sleeping."),
        SampleDay(daysAgo: 6, mood: 3, energy: 4, sleepHours: 7.0, stressLevel: 8, sleepQuality: 5, painLevel: 5, brainFogLevel: 5,
                  symptoms: [SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")],
                  basicsCompleted: ["Medications", "Hydration", "Ate well"],
                  freeNote: "Headache crept in this morning."),
        SampleDay(daysAgo: 5, mood: 2, energy: 3, sleepHours: 5.0, stressLevel: 8, sleepQuality: 3, painLevel: 3, brainFogLevel: 6,
                  symptoms: [],
                  basicsCompleted: ["Medications"],
                  freeNote: "Pulled another late one."),
        SampleDay(daysAgo: 4, mood: 4, energy: 5, sleepHours: 8.0, stressLevel: 3, sleepQuality: 7, painLevel: 4, brainFogLevel: 5,
                  symptoms: [
                      SymptomEntry(name: "Headache", severity: 5, emoji: "🤕"),
                      SymptomEntry(name: "Fatigue",  severity: 6, emoji: "😴"),
                  ],
                  basicsCompleted: ["Medications", "Hydration", "Movement", "Ate well", "Rest / nap"],
                  freeNote: "Crashed hard once the week eased up."),
        SampleDay(daysAgo: 3, mood: 3, energy: 6, sleepHours: 5.0, stressLevel: 5, sleepQuality: 4, painLevel: 1, brainFogLevel: 3,
                  symptoms: [],
                  basicsCompleted: ["Medications", "Hydration", "Movement"],
                  freeNote: ""),
        SampleDay(daysAgo: 2, mood: 5, energy: 7, sleepHours: 8.0, stressLevel: 4, sleepQuality: 8, painLevel: 4, brainFogLevel: 3,
                  symptoms: [SymptomEntry(name: "Headache", severity: 4, emoji: "🤕")],
                  basicsCompleted: ["Medications", "Hydration", "Movement", "Ate well"],
                  freeNote: "Better day overall."),
        SampleDay(daysAgo: 1, mood: 5, energy: 8, sleepHours: 8.0, stressLevel: 3, sleepQuality: 8, painLevel: 0, brainFogLevel: 2,
                  symptoms: [],
                  basicsCompleted: ["Medications", "Hydration", "Movement", "Ate well", "Self-care moment"],
                  freeNote: "Felt like myself again."),
    ]

    // 30-day extension covering daysAgo 8…37, generated deterministically from a
    // 12-day cycle. Each cycle has a 3-day high-stress streak (cycles 9-11),
    // a recovery day with fatigue (cycle 8), and poor-sleep nights at cycles
    // 5/9/11 followed by next-day headaches at cycles 4/8/10. Designed to
    // exercise the stress-fatigue and sleep-headache pattern detectors over
    // multiple streaks, while keeping the data plausible day-to-day.
    private static let extendedSampleDays: [SampleDay] = (8...37).map { generatedSampleDay(daysAgo: $0) }

    // 90-day extension picking up where extendedSampleDays leaves off (daysAgo
    // 38…127), same 12-day rhythm. Uses the richer symptom palette so the
    // longer PDF and history views show variety beyond Headache+Fatigue.
    private static let quarterSampleDays: [SampleDay] = (38...127).map { generatedSampleDay(daysAgo: $0, richSymptoms: true) }

    private static func generatedSampleDay(daysAgo: Int, richSymptoms: Bool = false) -> SampleDay {
        let cycle = daysAgo % 12
        let isHighStress    = (cycle == 9 || cycle == 10 || cycle == 11)
        let isPostStressDay = (cycle == 8)
        let isPoorSleep     = (cycle == 5 || cycle == 9 || cycle == 11)
        let isHeadacheDay   = (cycle == 4 || cycle == 8 || cycle == 10)

        let stress: Int = {
            if isHighStress { return cycle == 10 ? 9 : 8 }
            if cycle < 4    { return 3 + cycle }
            return 5
        }()
        let sleep: Double = isPoorSleep ? 5.0 : 7.0 + Double(cycle % 3) * 0.5
        let sleepQuality  = isPoorSleep ? 3 : (cycle.isMultiple(of: 3) ? 8 : 6)

        let mood: Int = {
            if isPostStressDay { return 3 }
            if sleep > 7.5     { return 5 }
            if sleep > 6.5     { return 4 }
            return 2
        }()
        let energy: Int = {
            if isPostStressDay { return 4 }
            if sleep > 7.5     { return mood == 5 ? 8 : 7 }
            if sleep > 6.5     { return 6 }
            return 4
        }()

        var symptoms: [SymptomEntry] = []
        if isHeadacheDay   { symptoms.append(SymptomEntry(name: "Headache", severity: 5, emoji: "🤕")) }
        if isPostStressDay { symptoms.append(SymptomEntry(name: "Fatigue",  severity: 6, emoji: "😴")) }

        if richSymptoms {
            // Brain fog accompanies the post-stress crash.
            if isPostStressDay {
                symptoms.append(SymptomEntry(name: "Brain Fog", severity: 4, emoji: "🌫️"))
            }
            // Anxiety tracks the active high-stress streak.
            if isHighStress {
                symptoms.append(SymptomEntry(name: "Anxiety", severity: 6, emoji: "😰"))
            }
            // Mid-cycle pain flare every 12 days.
            if cycle == 6 {
                symptoms.append(SymptomEntry(name: "Pain", severity: 3, emoji: "⚡️"))
            }
            // Rarer flavours alternating across cycles for symptom-frequency variety.
            let cycleIndex = daysAgo / 12
            if cycle == 2 && cycleIndex.isMultiple(of: 2) {
                symptoms.append(SymptomEntry(name: "Nausea", severity: 4, emoji: "🤢"))
            }
            if cycle == 0 && !cycleIndex.isMultiple(of: 2) {
                symptoms.append(SymptomEntry(name: "Joint pain", severity: 3, emoji: "🦴"))
            }
        }

        return SampleDay(
            daysAgo: daysAgo,
            mood: mood,
            energy: energy,
            sleepHours: sleep,
            stressLevel: stress,
            sleepQuality: sleepQuality,
            painLevel: 1 + (cycle % 4),
            brainFogLevel: 2 + (cycle % 4),
            symptoms: symptoms,
            basicsCompleted: cycle.isMultiple(of: 2)
                ? ["Medications", "Hydration"]
                : ["Medications", "Hydration", "Movement"],
            freeNote: ""
        )
    }

    #endif
}
