import SwiftUI
import SwiftData

struct InsightHistoryView: View {
    @Query(sort: \InsightRecord.firstSeen, order: .reverse) private var records: [InsightRecord]

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "No insights yet",
                    systemImage: "sparkles",
                    description: Text("Patterns Cadence detects will be collected here as your logging history grows.")
                )
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.title).font(.subheadline.weight(.semibold))
                        Text(record.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text("First seen \(record.firstSeen.formatted(date: .abbreviated, time: .omitted))")
                            Text("· \(Int(record.confidence * 100))% confidence")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Insight History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
