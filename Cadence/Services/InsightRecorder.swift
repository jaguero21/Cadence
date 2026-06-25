import SwiftData

// Upserts InsightRecords for the currently-detected insights and reports which
// ones are brand new, so callers can notify the user about newly emerged
// patterns exactly once.
@MainActor
enum InsightRecorder {
    // Inserts a record for each insight not seen before (keyed by title) and
    // refreshes lastSeen/confidence for ones already known. Returns the records
    // that were newly created this call. Idempotent across repeated calls.
    @discardableResult
    static func record(_ insights: [InsightCard], context: ModelContext) -> [InsightRecord] {
        let existing = (try? context.fetch(FetchDescriptor<InsightRecord>())) ?? []
        var byKey = Dictionary(existing.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var newlyCreated: [InsightRecord] = []

        for card in insights {
            let key = card.title
            if let record = byKey[key] {
                record.lastSeen = .now
                record.confidence = card.confidence
            } else {
                let record = InsightRecord(
                    key: key,
                    title: card.title,
                    detail: card.detail,
                    category: card.category.rawValue,
                    confidence: card.confidence
                )
                context.insert(record)
                byKey[key] = record
                newlyCreated.append(record)
            }
        }
        try? context.save()
        return newlyCreated
    }
}
