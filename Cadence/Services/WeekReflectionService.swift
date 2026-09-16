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

    // Pure prompt builder (unit-tested): one compact line per logged day.
    // Returns nil when the week is too thin to summarize honestly.
    static func promptText(from logs: [DailyLogSnapshot]) -> String? {
        let sorted = logs.sorted { $0.date < $1.date }
        guard sorted.count >= minimumDays else { return nil }

        let dayFormat = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        var lines: [String] = []
        for logDay in sorted {
            var parts: [String] = []
            parts.append("mood \(logDay.mood)/5, energy \(logDay.energy)/10, sleep \(String(format: "%.1f", logDay.sleepHours))h")
            if !logDay.symptoms.isEmpty {
                let symptoms = logDay.symptoms.map { "\($0.name) \($0.severity)/10" }.joined(separator: ", ")
                parts.append("symptoms: \(symptoms)")
            }
            if !logDay.factors.isEmpty {
                parts.append("factors: \(logDay.factors.joined(separator: ", "))")
            }
            if !logDay.peaksAndValleysNote.isEmpty {
                parts.append("peaks & valleys: \"\(truncated(logDay.peaksAndValleysNote))\"")
            }
            if !logDay.freeNote.isEmpty {
                parts.append("note: \"\(truncated(logDay.freeNote))\"")
            }
            if !logDay.intentionsForTomorrow.isEmpty {
                parts.append("intentions: \"\(truncated(logDay.intentionsForTomorrow))\"")
            }
            lines.append("\(logDay.date.formatted(dayFormat)) — \(parts.joined(separator: "; "))")
        }
        return "Here are my diary entries for this week:\n" + lines.joined(separator: "\n")
            + "\n\nPlease summarize my week."
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

    // Best-effort generation; nil on any failure (unsupported device, thin
    // week, model error) — callers just hide the result.
    static func generate(from logs: [DailyLogSnapshot]) async -> String? {
        guard let prompt = promptText(from: logs) else { return nil }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isSupported else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions(hasMood: hasMood(in: logs), dayCount: logs.count))
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            Self.log.error("Week reflection generation failed: \(error, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }
}
