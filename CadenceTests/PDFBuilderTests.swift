import Testing
import PDFKit
@testable import Cadence

@MainActor
@Suite struct PDFBuilderTests {
    // Smoke test: the single report builds a readable PDF from real logs and
    // a weekly review. Guards the whole render path (incl. the folded-in
    // weekly reflections, once Task 3 lands) against crashing on real data.
    @Test("build produces a valid PDF from logs and reviews")
    func build_returnsValidPDF() async throws {
        var logs: [DailyLogSnapshot] = []
        for i in 0..<6 {
            let day = Calendar.current.date(byAdding: .day, value: -i, to: .now) ?? .now
            let log = DailyLog(date: day)
            log.mood = 3
            log.energy = 6
            log.sleepHours = 7
            log.sleepQuality = 6
            log.freeNote = "A note on day \(i)."
            logs.append(DailyLogSnapshot(log))
        }
        let review = WeeklyReview(weekStartDate: .now)
        review.overallRating = 4
        review.intentionsForTomorrow = "Wind down earlier."
        let reviewSnap = WeeklyReviewSnapshot(review)

        let url = await PDFBuilder.build(logs: logs, reviews: [reviewSnap])
        let resolved = try #require(url)
        let doc = try #require(PDFDocument(url: resolved))
        #expect(doc.pageCount >= 1)
    }

    // Recovered from the old embedded PDFBuilderTests suite (CadenceTests/PatternEngineTests.swift,
    // pre-5056e1c) when the two-report-type system collapsed into one. Ported from
    // `PDFBuilder.build(type: .doctor, ...)` to the current signature — the assertions target the
    // surviving `renderReport` path, which still carries the same section titles and footer.
    @Test("build renders the symptom-frequency section, severity, adherence line, and page footer")
    func build_rendersSymptomFrequencyAndFooter() async throws {
        var logs: [DailyLogSnapshot] = []
        for i in 0..<10 {
            let day = Calendar.current.date(byAdding: .day, value: -i, to: .now) ?? .now
            let log = DailyLog(date: day)
            log.mood = 3 + i % 3
            log.hkSteps = 8000
            if i % 2 == 0 {
                log.symptoms = [SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")]
            }
            if i % 3 == 0 {
                log.factors = ["Travel"]
            }
            logs.append(DailyLogSnapshot(log))
        }

        let url = await PDFBuilder.build(logs: logs, reviews: [])
        let resolved = try #require(url)
        let document = try #require(PDFDocument(url: resolved))
        #expect(document.pageCount >= 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        #expect(text.contains("Symptoms"))
        #expect(text.contains("avg severity"))          // severity rides the frequency bars
        #expect(text.contains("days logged"))           // header adherence line
        #expect(text.contains("Page 1"))                // per-page footer
    }

    @Test("build with empty logs and reviews still produces a valid single-page PDF")
    func build_withEmptyData_producesSinglePage() async throws {
        let url = await PDFBuilder.build(logs: [], reviews: [])
        let resolved = try #require(url)
        let document = try #require(PDFDocument(url: resolved))
        #expect(document.pageCount == 1)
    }

    // Weekly reflections fold the retired Personal Summary's review content
    // (star rating, prompt responses, weekly intentions) into the report. A
    // page-count comparison is too weak a guard once this content actually
    // renders, so assert the extracted PDF text directly carries the section
    // header and the review's own distinctive content.
    @Test("weekly reviews render as a Weekly reflections section")
    func build_withReviews_rendersContent() async throws {
        let day = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let log = DailyLog(date: day)
        log.mood = 3
        let logs = [DailyLogSnapshot(log)]

        let review = WeeklyReview(weekStartDate: .now)
        review.overallRating = 5
        review.intentionsForTomorrow = "Distinctive weekly intentions marker XYZZY-42."
        let withReview = await PDFBuilder.build(logs: logs, reviews: [WeeklyReviewSnapshot(review)])

        let resolved = try #require(withReview)
        let document = try #require(PDFDocument(url: resolved))
        #expect(document.pageCount >= 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        #expect(text.contains("Weekly reflections"))
        #expect(text.contains("Distinctive weekly intentions marker XYZZY-42."))
    }
}
