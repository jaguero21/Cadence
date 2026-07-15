import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationService) private var notificationService
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @State private var editing: Medication?
    @State private var showingAdd = false

    var body: some View {
        List {
            if medications.isEmpty {
                ContentUnavailableView(
                    "No medications",
                    systemImage: "pills",
                    description: Text("Add the medications and supplements you take so Cadence can correlate them with your symptoms.")
                )
            } else {
                ForEach(medications) { med in
                    Button {
                        editing = med
                    } label: {
                        row(med)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    offsets.forEach { modelContext.delete(medications[$0]) }
                    // Deleted meds must not keep firing reminders.
                    let snapshots = medications
                        .enumerated()
                        .filter { !offsets.contains($0.offset) }
                        .map { MedicationSnapshot($0.element) }
                    Task { [notificationService] in
                        await notificationService.syncMedicationReminders(snapshots)
                    }
                }
            }
        }
        .navigationTitle("Medications")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            MedicationEditSheet(medication: nil)
        }
        .sheet(item: $editing) { med in
            MedicationEditSheet(medication: med)
        }
    }

    private func row(_ med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(med.displayLabel).font(.body)
                Spacer()
                if med.isActive {
                    Text("Active")
                        .font(.caption2.bold())
                        .foregroundStyle(CadenceColor.successGreen)
                } else {
                    Text("Stopped")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(dateRange(med))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dateRange(_ med: Medication) -> String {
        let fmt = Date.FormatStyle().month(.abbreviated).day().year()
        let start = med.startDate.formatted(fmt)
        if let end = med.endDate { return "\(start) – \(end.formatted(fmt))" }
        return "Since \(start)"
    }
}

private struct MedicationEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.notificationService) private var notificationService

    let medication: Medication?

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var startDate: Date = .now
    @State private var hasEnded: Bool = false
    @State private var endDate: Date = .now
    @State private var notes: String = ""
    @State private var reminderTimes: [Date] = []

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Sumatriptan)", text: $name)
                    TextField("Dosage (e.g. 50 mg)", text: $dosage)
                }
                Section {
                    DatePicker("Started", selection: $startDate, displayedComponents: .date)
                    Toggle("No longer taking", isOn: $hasEnded.animation())
                    if hasEnded {
                        DatePicker("Stopped", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section {
                    ForEach(reminderTimes.indices, id: \.self) { index in
                        DatePicker("Reminder \(index + 1)",
                                   selection: $reminderTimes[index],
                                   displayedComponents: .hourAndMinute)
                    }
                    .onDelete { reminderTimes.remove(atOffsets: $0) }
                    Button {
                        // Next new slot defaults to 9:00 am — a common dose time.
                        let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
                        reminderTimes.append(nine)
                    } label: {
                        Label("Add reminder time", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A daily notification for each time, while this medication is active. Swipe a time to remove it.")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(medication == nil ? "New Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let medication else { return }
        name = medication.name
        dosage = medication.dosage
        startDate = medication.startDate
        if let end = medication.endDate {
            hasEnded = true
            endDate = end
        }
        notes = medication.notes
        reminderTimes = medication.reminderMinutes.sorted().map(Medication.timeToday(fromMinute:))
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let resolvedEnd = hasEnded ? endDate : nil
        let minutes = Array(Set(reminderTimes.map(Medication.minuteOfDay(from:)))).sorted()
        if let medication {
            medication.name = trimmedName
            medication.dosage = dosage
            medication.startDate = Calendar.current.startOfDay(for: startDate)
            medication.endDate = resolvedEnd.map { Calendar.current.startOfDay(for: $0) }
            medication.notes = notes
            medication.reminderMinutes = minutes
        } else {
            modelContext.insert(Medication(name: trimmedName, dosage: dosage, startDate: startDate, endDate: resolvedEnd, notes: notes, reminderMinutes: minutes))
        }
        // Reconcile scheduled notifications with the whole store (this med's
        // times may have changed, another's course may have ended). Asking for
        // permission only when a reminder actually exists keeps the prompt
        // honest; the fetch runs before dismiss so the context is still live.
        let snapshots = ((try? modelContext.fetch(FetchDescriptor<Medication>())) ?? []).map(MedicationSnapshot.init)
        let needsPermission = !minutes.isEmpty
        Task { [notificationService] in
            if needsPermission {
                await notificationService.requestAuthorization()
            }
            await notificationService.syncMedicationReminders(snapshots)
        }
        dismiss()
    }
}
