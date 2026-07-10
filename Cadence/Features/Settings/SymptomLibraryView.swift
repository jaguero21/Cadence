import SwiftUI
import SwiftData

// Settings → Symptoms: every available symptom as a toggle. ON puts the chip
// on the daily log's symptom picker (and, since every library name maps to a
// HealthKit symptom type, enables two-way Health sync for it); OFF removes it
// from the picker. History is safe either way — logged days keep their
// entries, and the picker renders unlisted chips for them.
//
// A toggle inserts/deletes the SymptomTag row itself (dedup by name at save
// time, per the CloudKit rules) rather than carrying an isEnabled flag, so
// the picker's existing @Query needs no changes.
struct SymptomLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @Query(sort: \SymptomTag.sortOrder) private var tags: [SymptomTag]
    @State private var showingAddSheet = false
    @State private var saveError: String?

    // Defaults first (their familiar order), then the optional library.
    private var library: [(name: String, emoji: String)] {
        SymptomTag.defaults.map { ($0.name, $0.emoji) } + SymptomTag.optionalCatalog
    }

    // User-created tags that aren't part of the library — managed by deletion,
    // not toggling, because their definition lives only in the store.
    private var customTags: [SymptomTag] {
        let libraryNames = Set(library.map { $0.name.lowercased() })
        return tags.filter { !libraryNames.contains($0.name.lowercased()) }
    }

    var body: some View {
        List {
            Section {
                ForEach(library, id: \.name) { item in
                    Toggle(isOn: binding(for: item)) {
                        HStack(spacing: 10) {
                            Text(item.emoji)
                            Text(item.name)
                        }
                    }
                }
            } header: {
                Text("Symptom Library")
            } footer: {
                Text("Symptoms you turn on appear in the daily log's picker and sync with Apple Health. Turning one off never changes days you already logged.")
            }

            Section {
                ForEach(customTags) { tag in
                    HStack(spacing: 10) {
                        Text(tag.emoji)
                        Text(tag.name)
                    }
                }
                .onDelete { offsets in
                    let toDelete = customTags
                    offsets.forEach { modelContext.delete(toDelete[$0]) }
                    persist()
                }

                if store.isPro {
                    Button("Add custom symptom") {
                        showingAddSheet = true
                    }
                    .foregroundStyle(CadenceColor.accent)
                } else {
                    Button {
                        appState.showingProPaywall = true
                    } label: {
                        Label("Upgrade to add custom symptoms", systemImage: "lock.fill")
                    }
                    .foregroundStyle(CadenceColor.sleepPurple)
                }
            } header: {
                Text("Custom")
            } footer: {
                if !store.isPro {
                    Text("Custom symptoms beyond the library require Pro.")
                }
            }
        }
        .navigationTitle("Symptoms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSheet) {
            AddSymptomSheet(onSave: { _, _ in })
        }
        .alert("Couldn't Save", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func binding(for item: (name: String, emoji: String)) -> Binding<Bool> {
        Binding(
            get: { tags.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame } },
            set: { enabled in setSymptom(item, enabled: enabled) }
        )
    }

    private func setSymptom(_ item: (name: String, emoji: String), enabled: Bool) {
        if enabled {
            // Save-time dedup: a tag may already exist (CloudKit sync, rapid taps).
            guard !tags.contains(where: { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }) else { return }
            let defaultIndex = SymptomTag.defaults.firstIndex { $0.name == item.name }
            let catalogIndex = SymptomTag.optionalCatalog.firstIndex { $0.name == item.name }
            // Defaults keep their seeded order; library entries sort after them.
            let sortOrder = defaultIndex ?? (100 + (catalogIndex ?? 0))
            modelContext.insert(SymptomTag(
                name: item.name,
                emoji: item.emoji,
                isDefault: defaultIndex != nil,
                sortOrder: sortOrder
            ))
        } else {
            for tag in tags where tag.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame {
                modelContext.delete(tag)
            }
        }
        persist()
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            saveError = String(localized: "Couldn't update the symptom list. Please try again.")
        }
    }
}
