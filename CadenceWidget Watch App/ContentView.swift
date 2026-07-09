import SwiftUI

struct ContentView: View {
    private enum SendState {
        case idle, sent, queued
    }

    @State private var mood = 3
    @State private var energy = 5
    @State private var sendState: SendState = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Quick Log").font(.headline)

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            mood = value
                            sendState = .idle
                        } label: {
                            Text(MoodScale.emoji(for: value))
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
                        .onChange(of: energy) { _, _ in sendState = .idle }
                }

                Button {
                    WatchConnectivityManager.shared.sendQuickLog(mood: mood, energy: energy) { state in
                        Task { @MainActor in
                            sendState = state == .sent ? .sent : .queued
                        }
                    }
                } label: {
                    Text(buttonLabel)
                        .frame(maxWidth: .infinity)
                }
                .tint(sendState == .idle ? Color.accentColor : .green)

                if sendState == .queued {
                    Text("Will sync when your iPhone is nearby.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }

    private var buttonLabel: String {
        switch sendState {
        case .idle:   return String(localized: "Save to iPhone")
        case .sent:   return String(localized: "Sent ✓")
        case .queued: return String(localized: "Queued ✓")
        }
    }
}

#Preview {
    ContentView()
}
