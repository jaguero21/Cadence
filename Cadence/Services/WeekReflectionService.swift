import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    static let instructions = """
        You are a gentle journaling assistant inside a personal wellness app. \
        Summarize the user's week from their own diary entries in 3 to 5 \
        sentences, addressed to them in the second person ("You…"). Only \
        reflect what the entries actually say — never invent facts, never \
        give advice or suggestions, never diagnose, and never use medical \
        terminology beyond words the user wrote themselves. Warm, plain, \
        specific language. This is awareness, not medical guidance.
        """

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
            let session = LanguageModelSession(instructions: instructions)
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
