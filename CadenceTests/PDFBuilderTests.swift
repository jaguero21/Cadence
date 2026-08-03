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
}