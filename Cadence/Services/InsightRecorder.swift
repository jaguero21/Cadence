import Foundation
import SwiftData
import OSLog

// Upserts InsightRecords for the currently-detected insights and reports which
// ones are brand new, so callers can notify the user about newly emerged
// patterns exactly once.
@MainActor
enum InsightRecorder {
    private static let log = Logger(subsystem: "com.carpecadence", category: "InsightRecorder")

    // Canonical pipeline shared by every surface (Insights tab, foreground
    // notification check): same window, same inputs, same engine — so the
    // notification path can never advertise a pattern the tab doesn't show.
    static func currentInsights(context: ModelContext) -> [InsightCard] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -PatternThreshold.insightWindowDays, to: .now) ?? .distantPast
        let logs = (try? context.fetch(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date >= cutoff })
        )) ?? []
        let medications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        return PatternEngine.allInsights(
            from: logs.map(DailyLogSnapshot.init),
            medications: medications.map(MedicationSnapshot.init)
        )
    }

    @discardableResult
    static func detectAndRecord(context: ModelContext) -> [InsightRecord] {
        record(currentInsights(context: context), context: context)
    }

    // Inserts a record for each insight not seen before (keyed by the card's
    // stable semantic key) and refreshes the copy/confidence of known ones in
    // place — a medication insight flipping direction updates the same record.
    // Returns the records newly created AND persisted this call; on save
    // failure nothing is reported as new, so the once-per-pattern notification
    // guarantee survives a failed save (the next pass retries).
    @discardableResult
    static func record(_ insights: [InsightCard], context: ModelContext) -> [InsightRecord] {
        let existing = (try? context.fetch(FetchDescriptor<InsightRecord>())) ?? []
        var byKey = Dictionary(existing.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var newlyCreated: [InsightRecord] = []
        var mutated = false

        for card in insights {
            if let record = byKey[card.key] {
                if record.title != card.title || record.detail != card.detail || record.confidence != card.confidence {
                    record.title = card.title
                    record.detail = card.detail
                    record.confidence = card.confidence
                    record.lastSeen = .now
                    mutated = true
                }
            } else {
                let record = InsightRecord(
                    key: card.key,
                    title: card.title,
                    detail: card.detail,
                    category: card.category.rawValue,
                    confidence: card.confidence
                )
                context.insert(record)
                byKey[card.key] = record
                newlyCreated.append(record)
            }
        }

        guard !newlyCreated.isEmpty || mutated else { return [] }
        do {
            try context.save()
            return newlyCreated
        } catch {
            Self.log.error("Failed to persist insight records: \(error.localizedDescription)")
            return []
        }
    }
}
