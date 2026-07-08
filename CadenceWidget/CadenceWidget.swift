import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    // Staleness resolution lives in WidgetData.resolved (shared with the app
    // target and unit-tested there): the stored summary describes the day it
    // was written and must be reinterpreted after midnight.
    private func currentSummary() -> WidgetData.Summary {
        WidgetData.resolved(WidgetData.read())
    }

    func placeholder(in context: Context) -> CadenceEntry {
        CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 5))
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        completion(CadenceEntry(date: .now, summary: currentSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let entry = CadenceEntry(date: .now, summary: currentSummary())
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
}

struct CadenceWidgetEntryView: View {
    var entry: CadenceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
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
            } else {
                Label("Not logged yet", systemImage: "circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct CadenceWidget: Widget {
    let kind = "CadenceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CadenceWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cadence")
        .description("Your logging streak and today's check-in.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    CadenceWidget()
} timeline: {
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: false, streak: 3))
    CadenceEntry(date: .now, summary: WidgetData.Summary(date: .now, loggedToday: true, streak: 4))
}
