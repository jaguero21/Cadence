import SwiftUI

struct ContentView: View {
    private enum SendState {
        case idle, sent, queued
    }

    @State private var mood = 3
    @State private var energy = 5
    @State private var energyEdited = false
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

                // watchOS draws a Stepper's label large BETWEEN its − and +
                // buttons, and .labelsHidden() doesn't remove it there: the old
                // Stepper("Energy") rendered a giant clipped "En…" that pushed
                // the controls off screen. The label is the value instead, with
                // the metric name as a caption above.
                VStack(spacing: 2) {
                    Text("Energy").font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $energy, in: 0...10) {
                        Text("\(energy)")
                            .font(.title3.monospacedDigit())
                    }
                    .accessibilityLabel("Energy")
                    .accessibilityValue("\(energy) out of 10")
                    .onChange(of: energy) { _, _ in
                        sendState = .idle
                        energyEdited = true
                    }
                }

                Button {
                    WatchConnectivityManager.shared.sendQuickLog(mood: mood, energy: energyEdited ? energy : nil) { state in
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
