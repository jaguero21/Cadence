import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
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

    let medication: Medication?

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var startDate: Date = .now
    @State private var hasEnded: Bool = false
    @State private var endDate: Date = .now
    @State private var notes: String = ""

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
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let resolvedEnd = hasEnded ? endDate : nil
        if let medication {
            medication.name = trimmedName
            medication.dosage = dosage
            medication.startDate = Calendar.current.startOfDay(for: startDate)
            medication.endDate = resolvedEnd.map { Calendar.current.startOfDay(for: $0) }
            medication.notes = notes
        } else {
            modelContext.insert(Medication(name: trimmedName, dosage: dosage, startDate: startDate, endDate: resolvedEnd, notes: notes))
        }
        dismiss()
    }
}
