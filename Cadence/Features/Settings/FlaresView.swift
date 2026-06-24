import SwiftUI
import SwiftData

struct FlaresView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flare.startDate, order: .reverse) private var flares: [Flare]
    @State private var editing: Flare?
    @State private var showingAdd = false

    private var active: [Flare] { flares.filter(\.isActive) }
    private var past: [Flare] { flares.filter { !$0.isActive } }

    var body: some View {
        List {
            if flares.isEmpty {
                ContentUnavailableView(
                    "No flares logged",
                    systemImage: "flame",
                    description: Text("Record a flare when symptoms worsen for several days so you can track how often they happen and how long they last.")
                )
            } else {
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { flare in
                            Button { editing = flare } label: { row(flare) }
                                .tint(.primary)
                                .swipeActions(edge: .trailing) {
                                    Button("End") { endFlare(flare) }.tint(CadenceColor.successGreen)
                                }
                        }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { flare in
                            Button { editing = flare } label: { row(flare) }
                                .tint(.primary)
                        }
                        .onDelete { offsets in
                            offsets.forEach { modelContext.delete(past[$0]) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Flares")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { FlareEditSheet(flare: nil) }
        .sheet(item: $editing) { flare in FlareEditSheet(flare: flare) }
    }

    private func row(_ flare: Flare) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dateRange(flare)).font(.body)
                Spacer()
                Text("Peak \(flare.peakSeverity)/10")
                    .font(.caption2.bold())
                    .foregroundStyle(CadenceColor.stressRed)
            }
            HStack(spacing: 8) {
                Text("\(flare.durationDays) day\(flare.durationDays == 1 ? "" : "s")")
                if flare.isActive {
                    Text("• ongoing").foregroundStyle(CadenceColor.stressRed)
                }
                if !flare.note.isEmpty {
                    Text("• \(flare.note)").lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func dateRange(_ flare: Flare) -> String {
        let fmt = Date.FormatStyle().month(.abbreviated).day().year()
        let start = flare.startDate.formatted(fmt)
        if let end = flare.endDate { return "\(start) – \(end.formatted(fmt))" }
        return "Since \(start)"
    }

    private func endFlare(_ flare: Flare) {
        flare.endDate = Calendar.current.startOfDay(for: .now)
    }
}

private struct FlareEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let flare: Flare?

    @State private var startDate: Date = .now
    @State private var isOngoing: Bool = true
    @State private var endDate: Date = .now
    @State private var peakSeverity: Double = 5
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Started", selection: $startDate, displayedComponents: .date)
                    Toggle("Still ongoing", isOn: $isOngoing.animation())
                    if !isOngoing {
                        DatePicker("Ended", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section("Peak severity") {
                    HStack {
                        Slider(value: $peakSeverity, in: 1...10, step: 1)
                        Text("\(Int(peakSeverity))/10")
                            .monospacedDigit()
                            .foregroundStyle(CadenceColor.stressRed)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $note, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle(flare == nil ? "New Flare" : "Edit Flare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let flare else { return }
        startDate = flare.startDate
        if let end = flare.endDate {
            isOngoing = false
            endDate = end
        }
        peakSeverity = Double(flare.peakSeverity)
        note = flare.note
    }

    private func save() {
        let resolvedEnd = isOngoing ? nil : endDate
        if let flare {
            flare.startDate = Calendar.current.startOfDay(for: startDate)
            flare.endDate = resolvedEnd.map { Calendar.current.startOfDay(for: $0) }
            flare.peakSeverity = Int(peakSeverity)
            flare.note = note
        } else {
            modelContext.insert(Flare(startDate: startDate, endDate: resolvedEnd, peakSeverity: Int(peakSeverity), note: note))
        }
        dismiss()
    }
}
