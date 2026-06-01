import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreService.self) private var store
    @Query private var customSymptoms: [SymptomTag]
    @Environment(\.modelContext) private var modelContext

    @AppStorage("dailyReminderHour")   private var dailyHour: Int = 20
    @AppStorage("dailyReminderMinute") private var dailyMinute: Int = 0
    @AppStorage("weeklyReminderEnabled") private var weeklyEnabled: Bool = true
    @State private var showingAddSymptom = false

    var body: some View {
        NavigationStack {
            List {
                proSection
                remindersSection
                symptomsSection
                healthKitSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .task { await store.loadProducts() }
        .task { appState.notificationsAuthorized = await NotificationService.shared.checkAuthorizationStatus() }
        .task { appState.healthKitAuthorized = HealthKitService.shared.isAuthorized }
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
                        NotificationService.shared.scheduleDailyReminder(at: dailyHour, minute: dailyMinute)
                    }
                ),
                displayedComponents: .hourAndMinute
            )

            Toggle("Weekly review reminder (Sundays 7pm)", isOn: $weeklyEnabled)
                .onChange(of: weeklyEnabled) { _, on in
                    if on { NotificationService.shared.scheduleWeeklyReviewReminder() }
                    else  { NotificationService.shared.removeNotification(id: NotificationID.weeklyReview) }
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
            ForEach(customSymptoms.filter { !$0.isDefault }) { tag in
                HStack {
                    Text(tag.emoji)
                    Text(tag.name)
                }
            }
            .onDelete { offsets in
                let toDelete = customSymptoms.filter { !$0.isDefault }
                offsets.forEach { modelContext.delete(toDelete[$0]) }
            }

            Button("Add custom symptom") {
                showingAddSymptom = true
            }
            .foregroundStyle(CadenceColor.accent)
            .sheet(isPresented: $showingAddSymptom) {
                AddSymptomSheet(onSave: { _, _ in })
            }
        } header: {
            Label("Symptoms", systemImage: "tag.fill")
        } footer: {
            if !store.isPro {
                Text("Custom symptoms beyond 5 defaults require Pro.")
            }
        }
    }

    private var healthKitSection: some View {
        Section {
            Button("Re-authorize HealthKit") {
                Task {
                    appState.healthKitAuthorized = (try? await HealthKitService.shared.requestAuthorization()) ?? HealthKitService.shared.isAuthorized
                }
            }
            .foregroundStyle(CadenceColor.accent)
        } header: {
            Label("HealthKit", systemImage: "heart.fill")
        } footer: {
            if !HealthKitService.shared.isAvailable {
                Text("HealthKit is not available on this device.")
            } else if appState.healthKitAuthorized {
                Label("HealthKit access granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CadenceColor.successGreen)
            } else {
                HStack(spacing: 4) {
                    Label("HealthKit access denied.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(CadenceColor.stressRed)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            if let privacyURL = URL(string: "https://carpecadence.com/privacy") {
                Link("Privacy Policy", destination: privacyURL)
            }
            if let termsURL = URL(string: "https://carpecadence.com/terms") {
                Link("Terms of Service", destination: termsURL)
            }
        }
    }
}
