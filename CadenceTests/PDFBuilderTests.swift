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
            if i % 2 == 0 {
                log.symptoms = [SymptomEntry(name: "Headache", severity: 6, emoji: "🤕")]
            }
            if i % 3 == 0 {
                log.factors = ["Travel"]
            }
            // hk* moved off DailyLog into the local-only HealthSnapshot store;
            // the snapshot joins them, so supply one directly here.
            let health = HealthSnapshot(date: day)
            health.hkSteps = 8000
            logs.append(DailyLogSnapshot(log, health: health))
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

    // MARK: - Range, personal notes, long text, paper

    private func day(_ offset: Int) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now)
    }

    private func text(of url: URL?) throws -> (String, PDFDocument) {
        let resolved = try #require(url)
        let document = try #require(PDFDocument(url: resolved))
        return ((0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(), document)
    }

    @Test("Header coverage is measured against the chosen range, not the logs' own span")
    func header_usesChosenRange() async throws {
        // 3 logs in the last 3 days, inside a 10-day chosen range.
        let logs = (0..<3).map { DailyLogSnapshot(DailyLog(date: day(-$0))) }
        let url = await PDFBuilder.build(logs: logs, reviews: [], range: day(-9)...day(0))
        let (text, _) = try text(of: url)
        #expect(text.contains("3 of 10 days logged"))
    }

    @Test("Coverage never counts future days as missed")
    func coverage_capsAtToday() {
        let result = PDFBuilder.coverage(loggedDays: 2, range: day(-1)...day(5), today: .now)
        #expect(result.totalDays == 2)
    }

    @Test("Personal notes are left out unless included, and come after the clinical sections")
    func personalNotes_optionalAndLast() async throws {
        let log = DailyLog(date: day(0))
        log.freeNote = "Private diary marker QWERTY-7."
        log.symptoms = [SymptomEntry(name: "Headache", severity: 4, emoji: "🤕")]
        let logs = [DailyLogSnapshot(log)]

        let (without, _) = try text(of: await PDFBuilder.build(logs: logs, reviews: [], includePersonalNotes: false))
        #expect(!without.contains("QWERTY-7"))

        let (with, _) = try text(of: await PDFBuilder.build(logs: logs, reviews: [], includePersonalNotes: true))
        let note = try #require(with.range(of: "QWERTY-7"))
        let symptoms = try #require(with.range(of: "avg severity"))
        #expect(symptoms.lowerBound < note.lowerBound)
    }

    @Test("A note longer than a page is split across pages instead of running off the page")
    func longNote_spansPages() async throws {
        let log = DailyLog(date: day(0))
        log.freeNote = Array(repeating: "word", count: 6000).joined(separator: " ") + " ENDMARKER"
        let (text, document) = try text(of: await PDFBuilder.build(logs: [DailyLogSnapshot(log)], reviews: []))
        #expect(document.pageCount >= 3)
        #expect(text.contains("ENDMARKER"))
    }

    @Test("Letter paper in the US, A4 elsewhere")
    func paperSizeByRegion() {
        #expect(PDFBuilder.PaperSize.forRegion("US") == .letter)
        #expect(PDFBuilder.PaperSize.forRegion("MX") == .letter)
        #expect(PDFBuilder.PaperSize.forRegion("ES") == .a4)
        #expect(PDFBuilder.PaperSize.forRegion(nil) == .a4)
    }

    @Test("Letter reports use Letter pages and carry a document title")
    func letterPagesAndTitle() async throws {
        let url = await PDFBuilder.build(logs: [DailyLogSnapshot(DailyLog(date: day(0)))], reviews: [], paper: .letter)
        let (_, document) = try text(of: url)
        let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(bounds.width == 612 && bounds.height == 792)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == PDFBuilder.reportTitle)
    }

    @Test("The file name is readable and carries the range")
    func readableFileName() async throws {
        let url = try #require(await PDFBuilder.build(logs: [], reviews: [], range: day(-29)...day(0)))
        #expect(url.lastPathComponent.hasPrefix("Cadence Report, "))
        #expect(url.pathExtension == "pdf")
        #expect(!url.lastPathComponent.contains("/"))
    }
}
