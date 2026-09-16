import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

// Every word the prompt is built from, as a value. The builder takes this as a
// parameter rather than reading the catalog inline so tests can build a Spanish
// prompt without changing the device language — `String(localized:locale:)` does
// not reliably select another language's strings.
struct ReflectionStrings: Sendable, Equatable {
    let instructionsBody: String   // one %@: the sentence-range phrase
    let sentenceRange: String      // two %lld: lower and upper bound
    let moodRule: String
    let header: String
    let closing: String
    let trendHeader: String
    let moodLabel: String
    let energyLabel: String
    let sleepLabel: String
    let symptomsLabel: String
    let factorsLabel: String
    let peaksLabel: String
    let noteLabel: String
    let intentionsLabel: String
    let moodWords: [Int: String]
    let moodName: String
    let energyName: String
    let rose: String
    let dipped: String
    let eased: String
    let gotStronger: String
    let heldSteady: String

    // The app's language. Keys are explicit so translators see one reflection
    // group, and so the long instruction text isn't itself a catalog key.
    static var current: ReflectionStrings {
        ReflectionStrings(
            instructionsBody: String(localized: "reflection.instructions", defaultValue: """
                You are a gentle journaling assistant inside a personal wellness app. \
                Summarize the user's week from their own diary entries in %@, \
                addressed to them in the second person ("You…"). Only reflect what the \
                entries actually say — never invent facts, never give advice or \
                suggestions, never diagnose, and never use medical terminology beyond \
                words the user wrote themselves. Warm, plain, specific language. This \
                is awareness, not medical guidance. Describe changes only as the \
                "Over the week" lines state them, and don't call energy or sleep low \
                or high.
                """, comment: "Instructions sent to the on-device model. %@ is a phrase like '3 to 5 sentences'."),
            sentenceRange: String(localized: "reflection.sentenceRange", defaultValue: "%1$lld to %2$lld sentences",
                                  comment: "How long the reflection should be."),
            moodRule: String(localized: "reflection.moodRule", defaultValue: "Describe mood with the mood word given.",
                             comment: "Extra instruction, added only when the week recorded a mood."),
            header: String(localized: "reflection.header", defaultValue: "Here are my diary entries for this week:",
                           comment: "First line of the prompt."),
            closing: String(localized: "reflection.closing", defaultValue: "Please summarize my week.",
                            comment: "Last line of the prompt."),
            trendHeader: String(localized: "reflection.trendHeader", defaultValue: "Over the week:",
                                comment: "Introduces the computed trend sentences."),
            moodLabel: String(localized: "reflection.label.mood", defaultValue: "mood", comment: "Prompt label for the mood rating."),
            energyLabel: String(localized: "reflection.label.energy", defaultValue: "energy", comment: "Prompt label for the energy rating."),
            sleepLabel: String(localized: "reflection.label.sleep", defaultValue: "sleep", comment: "Prompt label for hours slept."),
            symptomsLabel: String(localized: "reflection.label.symptoms", defaultValue: "symptoms", comment: "Prompt label for the day's symptoms."),
            factorsLabel: String(localized: "reflection.label.factors", defaultValue: "factors", comment: "Prompt label for the day's factors."),
            peaksLabel: String(localized: "reflection.label.peaks", defaultValue: "peaks & valleys", comment: "Prompt label for the peaks and valleys note."),
            noteLabel: String(localized: "reflection.label.note", defaultValue: "note", comment: "Prompt label for the one-line note."),
            intentionsLabel: String(localized: "reflection.label.intentions", defaultValue: "intentions", comment: "Prompt label for tomorrow's intentions."),
            moodWords: [
                1: String(localized: "reflection.mood.1", defaultValue: "very sad", comment: "Mood 1 of 5, as sent to the model."),
                2: String(localized: "reflection.mood.2", defaultValue: "sad", comment: "Mood 2 of 5, as sent to the model."),
                3: String(localized: "reflection.mood.3", defaultValue: "neutral", comment: "Mood 3 of 5, as sent to the model."),
                4: String(localized: "reflection.mood.4", defaultValue: "happy", comment: "Mood 4 of 5, as sent to the model."),
                5: String(localized: "reflection.mood.5", defaultValue: "very happy", comment: "Mood 5 of 5, as sent to the model."),
            ],
            moodName: String(localized: "reflection.trend.moodName", defaultValue: "Mood", comment: "Subject of the mood trend sentence."),
            energyName: String(localized: "reflection.trend.energyName", defaultValue: "Energy", comment: "Subject of the energy trend sentence."),
            rose: String(localized: "reflection.trend.rose", defaultValue: "rose", comment: "Trend verb: the rating ended higher."),
            dipped: String(localized: "reflection.trend.dipped", defaultValue: "dipped", comment: "Trend verb: the rating ended lower."),
            eased: String(localized: "reflection.trend.eased", defaultValue: "eased", comment: "Trend verb: the symptom ended milder."),
            gotStronger: String(localized: "reflection.trend.gotStronger", defaultValue: "got stronger", comment: "Trend verb: the symptom ended worse."),
            heldSteady: String(localized: "reflection.trend.heldSteady", defaultValue: "held steady", comment: "Trend verb: no change from first to last.")
        )
    }
}

// On-device weekly reflection (iOS 26 FoundationModels): turns the week's own
// entries into a short second-person summary shown at the start of the weekly
// review. Strictly awareness framing — the instructions forbid advice,
// diagnosis, and invented facts; the model may only mirror what the user
// wrote. Everything runs on the device; nothing is ever sent anywhere.
enum WeekReflectionService {
    private static let log = Logger(subsystem: "com.carpecadence", category: "WeekReflection")

    // At least this many logged days before a "week summary" is honest.
    static let minimumDays = 2
    // Keep free-text fields bounded so the prompt fits comfortably in the
    // on-device model's context window.
    static let noteCharacterLimit = 220

    // Built per week, not a constant: the sentence range follows how much the
    // week actually holds, and the mood rule is omitted when no day recorded a
    // mood — with the rule but no moods the model invents one ("the mood was
    // headache", 2 of 3 runs during evaluation).
    static func instructions(hasMood: Bool, dayCount: Int, strings s: ReflectionStrings = .current) -> String {
        let bounds = dayCount <= minimumDays ? (2, 3) : (3, 5)
        let range = String(format: s.sentenceRange, bounds.0, bounds.1)
        let body = String(format: s.instructionsBody, range)
        return hasMood ? body + " " + s.moodRule : body
    }

    static func hasMood(in logs: [DailyLogSnapshot]) -> Bool {
        logs.contains { $0.didEditMood }
    }

    // Pure prompt builder (unit-tested): one compact line per logged day, then
    // one line stating the direction of every change.
    //
    // Only fields the user actually edited are sent. DailyLog defaults mood to
    // 3, energy to 5 and sleep to 7 hours, and the old builder passed those
    // defaults on as if they were entries — a week whose note said "forgot to
    // fill most of this in" came back as "a mood of 3/5, energy at 5/10, sleep
    // at 7.0h" in 3 of 3 runs. PatternEngine and the Health write-back already
    // gate on these flags; this now does too.
    static func promptText(from logs: [DailyLogSnapshot],
                           strings s: ReflectionStrings = .current,
                           locale: Locale = .current) -> String? {
        let sorted = logs.sorted { $0.date < $1.date }
        guard sorted.count >= minimumDays else { return nil }

        let dayFormat = Date.FormatStyle(locale: locale).weekday(.abbreviated).month(.abbreviated).day()
        var lines: [String] = []
        var moods: [Int] = []
        var energies: [Int] = []
        var symptomSeries: [(name: String, values: [Int])] = []

        for logDay in sorted {
            var parts: [String] = []
            var metrics: [String] = []
            if logDay.didEditMood, let word = s.moodWords[logDay.mood] {
                metrics.append("\(s.moodLabel) \(logDay.mood)/5 (\(word))")
                moods.append(logDay.mood)
            }
            if logDay.didEditMetrics {
                metrics.append("\(s.energyLabel) \(logDay.energy)/10, \(s.sleepLabel) \(String(format: "%.1f", logDay.sleepHours))h")
                energies.append(logDay.energy)
            }
            if !metrics.isEmpty { parts.append(metrics.joined(separator: ", ")) }
            if !logDay.symptoms.isEmpty {
                let symptoms = logDay.symptoms.map { "\($0.name) \($0.severity)/10" }.joined(separator: ", ")
                parts.append("\(s.symptomsLabel): \(symptoms)")
                for symptom in logDay.symptoms {
                    if let index = symptomSeries.firstIndex(where: { $0.name == symptom.name }) {
                        symptomSeries[index].values.append(symptom.severity)
                    } else {
                        symptomSeries.append((symptom.name, [symptom.severity]))
                    }
                }
            }
            if !logDay.factors.isEmpty {
                parts.append("\(s.factorsLabel): \(logDay.factors.joined(separator: ", "))")
            }
            if !logDay.peaksAndValleysNote.isEmpty {
                parts.append("\(s.peaksLabel): \"\(truncated(logDay.peaksAndValleysNote))\"")
            }
            if !logDay.freeNote.isEmpty {
                parts.append("\(s.noteLabel): \"\(truncated(logDay.freeNote))\"")
            }
            if !logDay.intentionsForTomorrow.isEmpty {
                parts.append("\(s.intentionsLabel): \"\(truncated(logDay.intentionsForTomorrow))\"")
            }
            // A day where nothing was filled in tells the model nothing.
            guard !parts.isEmpty else { continue }
            lines.append("\(logDay.date.formatted(dayFormat)) — \(parts.joined(separator: "; "))")
        }

        guard lines.count >= minimumDays else { return nil }

        var trends: [String] = []
        if let verb = trendVerb(moods, higherIsWorse: false, strings: s) { trends.append("\(s.moodName) \(verb).") }
        if let verb = trendVerb(energies, higherIsWorse: false, strings: s) { trends.append("\(s.energyName) \(verb).") }
        for series in symptomSeries {
            if let verb = trendVerb(series.values, higherIsWorse: true, strings: s) {
                trends.append("\(series.name) \(verb).")
            }
        }

        var text = s.header + "\n" + lines.joined(separator: "\n")
        if !trends.isEmpty { text += "\n\n" + s.trendHeader + " " + trends.joined(separator: " ") }
        return text + "\n\n" + s.closing
    }

    // First vs last logged value. Verbs only — a numeric series in the prompt
    // gets recited back into the summary (8.4 numbers per output when that was
    // tried, against 1.0 with verbs).
    static func trendVerb(_ values: [Int], higherIsWorse: Bool, strings s: ReflectionStrings) -> String? {
        guard values.count >= 2, let first = values.first, let last = values.last else { return nil }
        if first == last { return s.heldSteady }
        if higherIsWorse { return last < first ? s.eased : s.gotStronger }
        return last > first ? s.rose : s.dipped
    }

    private static func truncated(_ text: String) -> String {
        text.count <= noteCharacterLimit ? text : String(text.prefix(noteCharacterLimit)) + "…"
    }

    // Whether this device can generate a reflection right now (iOS 26 with
    // Apple Intelligence available and the model downloaded).
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    // What the card should show. `blocked` is a guardrail hit or a model refusal,
    // which needs different copy from a plain failure — Apple's safety guidance
    // asks for a clear message when the input is what the feature can't handle.
    enum Outcome: Sendable, Equatable {
        case text(String)
        case unavailable
        case blocked
        case failed
    }

    // The card renders this verbatim, so formatting the model adds has to come
    // off. Pure and unit-tested.
    static func sanitize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\\*\\*|__|`", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^#{1,6}[ \t]*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Best-effort generation. Plain text on purpose: guided generation
    // (`@Generable`) was blocked by the guardrail on both medication weeks during
    // evaluation — 6 of 6, against 0 of 12 for every plain-text combination — and
    // medications are a first-class Cadence feature.
    static func generate(from logs: [DailyLogSnapshot],
                         strings: ReflectionStrings = .current,
                         locale: Locale = .current) async -> Outcome {
        guard let prompt = promptText(from: logs, strings: strings, locale: locale) else { return .unavailable }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isSupported else { return .unavailable }
        // Hide the card rather than answer in the wrong language: the model
        // translated Spanish entries into English before the prompt was localized.
        guard SystemLanguageModel.default.supportsLocale(locale) else { return .unavailable }
        let instructionText = instructions(hasMood: hasMood(in: logs), dayCount: logs.count, strings: strings)
        do {
            let session = LanguageModelSession(instructions: instructionText)
            let response = try await session.respond(to: prompt)
            let text = sanitize(response.content)
            return text.isEmpty ? .failed : .text(text)
        } catch {
            Self.log.error("Week reflection generation failed: \(error, privacy: .public)")
            if #available(iOS 27.0, *), let modelError = error as? LanguageModelError {
                switch modelError {
                case .guardrailViolation, .refusal: return .blocked
                default: return .failed
                }
            }
            return .failed
        }
        #else
        return .unavailable
        #endif
    }
}
