import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    // Staleness resolution lives in WidgetData.resolved (shared with the app
    // target and unit-tested there): the stored summary describes the day it
    // was written and must be reinterpreted after midnight.
    private func currentSummary() -> WidgetData.Summary {
        WidgetData.resolved(WidgetData.read())
    }

    func placeholder(in context: Context) -> CadenceEntry {
        CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 5, mascotPose: .welcoming))
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        completion(CadenceEntry(date: .now, summary: currentSummary(), pendingMood: WidgetData.pendingMood(on: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let entry = CadenceEntry(date: .now, summary: currentSummary(), pendingMood: WidgetData.pendingMood(on: .now))
        // Refresh after midnight so currentSummary() re-evaluates staleness for
        // the new day even if the app isn't opened.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let nextMidnight = Calendar.current.startOfDay(for: tomorrow)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct CadenceEntry: TimelineEntry {
    let date: Date
    let summary: WidgetData.Summary
    // A mood tapped on the widget that the app hasn't picked up yet.
    var pendingMood: Int?
}

struct CadenceWidgetEntryView: View {
    var entry: CadenceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline:      inlineView
        default:                    systemView
        }
    }

    // MARK: - Lock Screen / StandBy accessories

    // Tapping an accessory goes straight into today's log via the same
    // stash-and-open intent as the Control Center button — never logging
    // anything by itself (unchosen data is fake awareness).

    private var circularView: some View {
        Button(intent: OpenCheckInIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Image(systemName: entry.summary.loggedToday ? "checkmark.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(entry.summary.streak)")
                        .font(.system(.title3, design: .rounded).bold())
                        .contentTransition(.numericText())
                }
                .widgetAccentable()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.summary.loggedToday
            ? "Logged today. \(entry.summary.streak)-day streak."
            : "Not logged yet. \(entry.summary.streak)-day streak. Opens today's log.")
    }

    private var rectangularView: some View {
        Button(intent: OpenCheckInIntent()) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(entry.summary.streak)-day streak")
                        .font(.headline)
                        .contentTransition(.numericText())
                }
                .widgetAccentable()

                if entry.summary.loggedToday {
                    Label("Logged today", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                } else if let mood = entry.pendingMood {
                    Text("\(MoodScale.emoji(for: mood)) Mood saved")
                        .font(.caption)
                } else {
                    Text("Tap to check in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var inlineView: some View {
        Label(
            entry.summary.loggedToday
                ? "Streak \(entry.summary.streak) · logged"
                : "Streak \(entry.summary.streak) · check in",
            systemImage: "flame.fill"
        )
    }

    // MARK: - Home Screen / StandBy

    private var systemView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(entry.summary.streak)")
                    .font(.system(.title, design: .rounded).bold())
                    .contentTransition(.numericText())
                Text(entry.summary.streak == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // iOS 18 tinted Home Screens flatten colors; keep the streak
            // cluster legible as the accented element.
            .widgetAccentable()

            if family != .systemSmall {
                Text("logging streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.summary.loggedToday {
                Label("Logged today", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else if let mood = entry.pendingMood {
                // A tap was recorded but the app hasn't opened to persist it —
                // "saved", not "logged", stays truthful about the difference.
                Label("\(MoodScale.emoji(for: mood)) Mood saved", systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                moodButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            // .systemMedium only: task review measured a genuine bounding-box
            // overlap between a .systemSmall-sized 44×44 corner mascot and the
            // mood-buttons row on the smallest supported device class
            // (iPhone SE-class .systemSmall). .systemMedium has 100pt+ of
            // clearance at 56×56, comfortably safe.
            if family == .systemMedium {
                Image(entry.summary.mascotPose.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .opacity(0.5)
                    .accessibilityHidden(true)
                    .padding(.trailing, -4)
                    .padding(.bottom, -4)
            }
        }
    }

    // One-tap quick log straight from the home screen.
    private var moodButtons: some View {
        HStack(spacing: family == .systemSmall ? 2 : 6) {
            ForEach(1...5, id: \.self) { value in
                Button(intent: WidgetQuickLogIntent(mood: value)) {
                    Text(MoodScale.emoji(for: value))
                        .font(.system(size: family == .systemSmall ? 15 : 18))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log mood \(value) of 5")
            }
        }
    }
}

struct CadenceWidget: Widget {
    let kind = WidgetData.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CadenceWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cadence")
        .description("Your logging streak and today's check-in.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

#Preview(as: .systemSmall) {
    CadenceWidget()
} timeline: {
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 3, mascotPose: .welcoming))
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: true, streak: 4, mascotPose: .resting))
}

#Preview(as: .accessoryCircular) {
    CadenceWidget()
} timeline: {
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 3, mascotPose: .welcoming))
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: true, streak: 4, mascotPose: .resting))
}

#Preview(as: .accessoryRectangular) {
    CadenceWidget()
} timeline: {
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 3, mascotPose: .welcoming))
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: true, streak: 4, mascotPose: .resting))
}
