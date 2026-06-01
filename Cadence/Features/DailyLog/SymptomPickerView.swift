import SwiftUI
import SwiftData

struct SymptomPickerView: View {
    @Binding var selectedSymptoms: [SymptomEntry]
    @Query(sort: \SymptomTag.sortOrder) private var allTags: [SymptomTag]
    @State private var expandedTag: String?
    @State private var showingAddSheet = false
    @State private var newSymptomName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tap to select, hold to rate severity")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(allTags) { tag in
                    symptomChip(tag: tag)
                }
                addChip
            }
        }
    }

    private func symptomChip(tag: SymptomTag) -> some View {
        let isSelected = selectedSymptoms.contains { $0.name == tag.name }
        let severity = selectedSymptoms.first { $0.name == tag.name }?.severity ?? 5

        return VStack(spacing: 8) {
            Button {
                toggleSymptom(tag: tag)
            } label: {
                VStack(spacing: 6) {
                    Text(tag.emoji)
                        .font(.title2)
                    Text(tag.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isSelected ? CadenceColor.stressRed : CadenceColor.cardBG,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .hapticFeedback(.medium)

            if isSelected && expandedTag == tag.name {
                VStack(spacing: 4) {
                    Text("Severity: \(severity)")
                        .font(.caption.bold())
                    Slider(
                        value: Binding(
                            get: { Double(severity) },
                            set: { updateSeverity(tag: tag, value: Int($0.rounded())) }
                        ),
                        in: 1...10, step: 1
                    )
                    .tint(CadenceColor.stressRed)
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .onLongPressGesture {
            withAnimation(CadenceAnimation.spring) {
                expandedTag = expandedTag == tag.name ? nil : tag.name
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private var addChip: some View {
        Button {
            showingAddSheet = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(CadenceColor.moodBlue)
                Text("Add")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CadenceColor.cardBG, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingAddSheet) {
            AddSymptomSheet(onSave: { _, _ in showingAddSheet = false })
        }
    }

    private func toggleSymptom(tag: SymptomTag) {
        if let idx = selectedSymptoms.firstIndex(where: { $0.name == tag.name }) {
            selectedSymptoms.remove(at: idx)
            if expandedTag == tag.name { expandedTag = nil }
        } else {
            selectedSymptoms.append(SymptomEntry(name: tag.name, severity: 5, emoji: tag.emoji))
        }
    }

    private func updateSeverity(tag: SymptomTag, value: Int) {
        if let idx = selectedSymptoms.firstIndex(where: { $0.name == tag.name }) {
            selectedSymptoms[idx].severity = value.clamped(to: 1...10)
        }
    }
}

struct AddSymptomSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTags: [SymptomTag]
    let onSave: (String, String) -> Void
    @State private var name = ""
    @State private var emoji = "🔵"

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var isDuplicate: Bool {
        existingTags.contains { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptom name") {
                    TextField("e.g. Nausea", text: $name)
                }
                if isDuplicate {
                    Text("A symptom named \"\(trimmedName)\" already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Section("Emoji") {
                    TextField("Emoji", text: $emoji)
                        .onChange(of: emoji) { _, newValue in
                            let clamped = newValue.first.map(String.init) ?? ""
                            if emoji != clamped { emoji = clamped }
                        }
                }
            }
            .navigationTitle("New Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let tag = SymptomTag(name: trimmedName, emoji: emoji)
                        modelContext.insert(tag)
                        onSave(trimmedName, emoji)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || emoji.isEmpty || isDuplicate)
                }
            }
        }
    }
}
