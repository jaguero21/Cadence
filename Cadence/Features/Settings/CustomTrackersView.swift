import SwiftUI
import SwiftData

struct CustomTrackersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomTracker.sortOrder) private var trackers: [CustomTracker]
    @State private var editing: CustomTracker?
    @State private var showingAdd = false

    var body: some View {
        List {
            if trackers.isEmpty {
                ContentUnavailableView(
                    "No custom trackers",
                    systemImage: "slider.horizontal.3",
                    description: Text("Add your own 0–10 (or any range) trackers to log alongside the built-in metrics each day.")
                )
            } else {
                ForEach(trackers) { tracker in
                    Button { editing = tracker } label: {
                        HStack {
                            Text(tracker.name)
                            Spacer()
                            Text("\(tracker.minValue)–\(tracker.maxValue)\(tracker.unit.isEmpty ? "" : " \(tracker.unit)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    offsets.forEach { modelContext.delete(trackers[$0]) }
                }
            }
        }
        .navigationTitle("Custom Trackers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { CustomTrackerEditSheet(tracker: nil, nextSortOrder: trackers.count) }
        .sheet(item: $editing) { tracker in CustomTrackerEditSheet(tracker: tracker, nextSortOrder: trackers.count) }
    }
}

private struct CustomTrackerEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let tracker: CustomTracker?
    let nextSortOrder: Int

    @State private var name = ""
    @State private var unit = ""
    @State private var minValue = 0
    @State private var maxValue = 10

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && minValue < maxValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Joint pain)", text: $name)
                    TextField("Unit (optional, e.g. mg)", text: $unit)
                }
                Section("Range") {
                    Stepper("Minimum: \(minValue)", value: $minValue, in: 0...98)
                        .onChange(of: minValue) { _, newMin in
                            if maxValue <= newMin { maxValue = newMin + 1 }
                        }
                    Stepper("Maximum: \(maxValue)", value: $maxValue, in: (minValue + 1)...100)
                }
            }
            .navigationTitle(tracker == nil ? "New Tracker" : "Edit Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!isValid) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let tracker else { return }
        name = tracker.name
        unit = tracker.unit
        minValue = tracker.minValue
        maxValue = tracker.maxValue
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let tracker {
            tracker.name = trimmed
            tracker.unit = unit
            tracker.minValue = minValue
            tracker.maxValue = maxValue
        } else {
            modelContext.insert(CustomTracker(name: trimmed, minValue: minValue, maxValue: maxValue, unit: unit, sortOrder: nextSortOrder))
        }
        dismiss()
    }
}
