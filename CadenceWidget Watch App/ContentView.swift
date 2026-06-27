import SwiftUI

struct ContentView: View {
    @State private var mood = 3
    @State private var energy = 5
    @State private var sent = false

    private let moods = ["😢", "😕", "😐", "🙂", "😊"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Quick Log").font(.headline)

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            mood = value
                            sent = false
                        } label: {
                            Text(moods[value - 1])
                                .font(.title3)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(mood == value ? Color.accentColor.opacity(0.35) : Color.gray.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 2) {
                    Text("Energy: \(energy)").font(.caption)
                    Stepper("Energy", value: $energy, in: 0...10)
                        .labelsHidden()
                        .onChange(of: energy) { _, _ in sent = false }
                }

                Button {
                    WatchConnectivityManager.shared.sendQuickLog(mood: mood, energy: energy)
                    sent = true
                } label: {
                    Text(sent ? "Sent ✓" : "Save to iPhone")
                        .frame(maxWidth: .infinity)
                }
                .tint(sent ? .green : .accentColor)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
