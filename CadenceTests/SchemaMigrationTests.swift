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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(container.configurations.isEmpty == false)
    }

    @Test("In-memory container accepts DailyLog insert and fetch")
    func inMemoryContainer_acceptsDailyLogInsertAndFetch() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let log = DailyLog()
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.first?.didEditMood == false)
    }

    @Test("DailyLog hkSleepHours and sleepHours persist correctly")
    func dailyLog_sleepFields_persistRoundTrip() throws {
        let schema = Schema([DailyLog.self, WeeklyReview.self, SymptomTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let log = DailyLog()
        log.hkSleepHours = 7.5
        log.sleepHours = 7.5
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(fetched.first?.hkSleepHours == 7.5)
        #expect(fetched.first?.sleepHours == 7.5)
    }
}
