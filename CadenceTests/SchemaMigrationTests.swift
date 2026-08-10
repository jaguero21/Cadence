import Testing
import Foundation
import SwiftData
@testable import Cadence

// MARK: - SwiftData schema and container tests
//
// The app previously declared CadenceSchemaV1 / V2 and a lightweight migration plan, but both
// schema versions referenced identical model lists, making the plan a no-op. That dead code has
// been removed. SwiftData handles lightweight schema changes (new columns with default values)
// automatically when the container is initialised without a migration plan.

@Suite("SwiftData – schema and container")
struct SchemaMigrationTests {

    // MARK: Model registration

    @Test("Schema contains exactly the three expected model types")
    func schema_containsExpectedModelTypes() {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let typeNames = schema.entities.map(\.name)
        #expect(typeNames.contains("DailyLog"))
        #expect(typeNames.contains("WeeklyReview"))
        #expect(typeNames.contains("SymptomTag"))
        #expect(schema.entities.count == 3)
    }

    // MARK: In-memory container

    @Test("In-memory ModelContainer initialises without throwing")
    func inMemoryContainer_initialisesSuccessfully() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(container.configurations.isEmpty == false)
    }

    @Test("In-memory container accepts DailyLog insert and fetch")
    func inMemoryContainer_acceptsDailyLogInsertAndFetch() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let log = DailyLog()
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.count == 1)
    }

    @Test("In-memory container accepts WeeklyReview insert and fetch")
    func inMemoryContainer_acceptsWeeklyReviewInsertAndFetch() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let review = WeeklyReview(weekStartDate: .now)
        context.insert(review)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WeeklyReview>())
        #expect(fetched.count == 1)
    }

    @Test("In-memory container accepts SymptomTag insert and fetch")
    func inMemoryContainer_acceptsSymptomTagInsertAndFetch() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let tag = SymptomTag(name: "Headache", emoji: "🤕", isDefault: true)
        context.insert(tag)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SymptomTag>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Headache")
    }

    // MARK: DailyLog new fields

    @Test("DailyLog didEditMood defaults to false")
    func dailyLog_didEditMood_defaultsFalse() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let log = DailyLog()
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.first?.didEditMood == false)
    }

    // The user-entered sleep figure and the HealthKit-measured one deliberately
    // live in DIFFERENT stores now: DailyLog is mirrored to CloudKit, and
    // Guideline 5.1.3(ii) forbids putting personal health information there, so
    // every hk* value moved to HealthSnapshot on a local-only configuration.
    // This pins both halves round-tripping and, crucially, that they rejoin by
    // date — the join is what every consumer of hk* data depends on.
    @Test("User sleepHours and HealthKit hkSleepHours persist in separate stores and rejoin by date")
    func sleepFields_persistAcrossSplitStores() throws {
        let syncedSchema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let localSchema  = Schema([HealthSnapshot.self])
        let fullSchema   = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, HealthSnapshot.self])
        let synced = ModelConfiguration("Synced", schema: syncedSchema, isStoredInMemoryOnly: true)
        let local  = ModelConfiguration("Local",  schema: localSchema,  isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: fullSchema, configurations: [synced, local])
        let context = ModelContext(container)

        let day = Calendar.current.startOfDay(for: .now)
        let log = DailyLog(date: day)
        log.sleepHours = 7.5
        context.insert(log)

        let health = HealthSnapshot(date: day)
        health.hkSleepHours = 6.25
        context.insert(health)
        try context.save()

        let fetchedLog = try #require(try context.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(fetchedLog.sleepHours == 7.5)

        let fetchedHealth = try #require(HealthSnapshot.row(for: day, in: context))
        #expect(fetchedHealth.hkSleepHours == 6.25)

        // The join is what puts them back together for PatternEngine, the PDF,
        // the CSV and the charts.
        let joined = DailyLogSnapshot.build(from: [fetchedLog], in: context)
        #expect(joined.count == 1)
        #expect(joined.first?.sleepHours == 7.5)
        #expect(joined.first?.hkSleepHours == 6.25)
    }

    @Test("A log with no health row for its day joins to nil hk* values, not zeros")
    func joinWithoutHealthRow_yieldsNilNotZero() throws {
        let fullSchema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self, HealthSnapshot.self])
        let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: fullSchema, configurations: [config])
        let context = ModelContext(container)

        let log = DailyLog(date: .now)
        context.insert(log)
        try context.save()

        let joined = try #require(DailyLogSnapshot.build(from: [log], in: context).first)
        // nil, never 0 — a zero would read as "measured no steps / no sleep"
        // and would be charted and averaged as real data.
        #expect(joined.hkSteps == nil)
        #expect(joined.hkSleepHours == nil)
        #expect(joined.hkWorkoutMinutes == nil)
    }
}
