import Foundation
import FoundationModels

// Runs the SHIPPED WeekReflectionService against the on-device model, so a new
// model version can be checked in one command. See README.md.

// MARK: - Spanish strings, read from the shipped catalog

// The Spanish prompt the app will actually send. String(localized:) falls back to
// its defaultValue outside an app bundle, so the es values come from the catalog
// directly — otherwise this would test English wording twice.
func spanishStrings(catalogPath: String) throws -> ReflectionStrings {
    let data = try Data(contentsOf: URL(fileURLWithPath: catalogPath))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = json?["strings"] as? [String: Any] ?? [:]
    func value(_ key: String, _ fallback: String) -> String {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let es = localizations["es"] as? [String: Any],
              let unit = es["stringUnit"] as? [String: Any],
              let value = unit["value"] as? String
        else {
            FileHandle.standardError.write(Data("MISSING es for \(key)\n".utf8))
            return fallback
        }
        return value
    }
    return ReflectionStrings(
        instructionsBody: value("reflection.instructions", ""),
        sentenceRange: value("reflection.sentenceRange", ""),
        moodRule: value("reflection.moodRule", ""),
        header: value("reflection.header", ""),
        closing: value("reflection.closing", ""),
        trendHeader: value("reflection.trendHeader", ""),
        moodLabel: value("reflection.label.mood", ""),
        energyLabel: value("reflection.label.energy", ""),
        sleepLabel: value("reflection.label.sleep", ""),
        symptomsLabel: value("reflection.label.symptoms", ""),
        factorsLabel: value("reflection.label.factors", ""),
        peaksLabel: value("reflection.label.peaks", ""),
        noteLabel: value("reflection.label.note", ""),
        intentionsLabel: value("reflection.label.intentions", ""),
        moodWords: [
            1: value("reflection.mood.1", ""), 2: value("reflection.mood.2", ""),
            3: value("reflection.mood.3", ""), 4: value("reflection.mood.4", ""),
            5: value("reflection.mood.5", ""),
        ],
        moodName: value("reflection.trend.moodName", ""),
        energyName: value("reflection.trend.energyName", ""),
        rose: value("reflection.trend.rose", ""),
        dipped: value("reflection.trend.dipped", ""),
        eased: value("reflection.trend.eased", ""),
        gotStronger: value("reflection.trend.gotStronger", ""),
        heldSteady: value("reflection.trend.heldSteady", "")
    )
}

// MARK: - Run record

struct Run: Codable {
    let fixture: String
    let language: String
    let sample: Int
    let skippedForCrisisLanguage: Bool
    let prompt: String?
    let instructions: String?
    let output: String?
    let error: String?
}

// MARK: - Checks

func numbers(in text: String) -> Int {
    text.matches(of: /\d+(?:[.,]\d+)?/).count
}

func hasMarkdown(in text: String) -> Bool {
    text.contains("**") || text.contains("__") || text.contains("`") || text.hasPrefix("#")
}

// Sentence enders only: a period between digits is a decimal ("6.5h"), not the
// end of a sentence.
func sentenceCount(in text: String) -> Int {
    text.matches(of: /[.!?](?:\s|$)/).count
}

// The unedited-metrics week must come back with no mood, energy, or sleep in it.
// Symptom severities ARE in that week's entries, so they're fair to repeat.
func mentionsUnenteredRatings(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return ["mood", "energy", "slept", "sleep", "/5", "ánimo", "energía", "sueño"].contains { lowered.contains($0) }
}

// MARK: - Main

let samples = 3
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("Cadence/Localizable.xcstrings").path

let english = ReflectionStrings.current   // falls back to the in-code defaults, which are the English strings
let spanish = try spanishStrings(catalogPath: catalog)

guard case .available = SystemLanguageModel.default.availability else {
    print("The on-device model is unavailable here. Enable Apple Intelligence and re-run.")
    exit(1)
}

var runs: [Run] = []
for fixture in Fixtures.all {
    let strings = fixture.spanish ? spanish : english
    let locale = Locale(identifier: fixture.spanish ? "es_ES" : "en_US")
    let language = fixture.spanish ? "es" : "en"

    // Exactly what the card does: the crisis check runs before anything else.
    let written = fixture.logs.flatMap { [$0.freeNote, $0.peaksAndValleysNote, $0.intentionsForTomorrow] }
    if CrisisLanguage.matches(in: written) {
        runs.append(Run(fixture: fixture.name, language: language, sample: 0, skippedForCrisisLanguage: true,
                        prompt: nil, instructions: nil, output: nil, error: nil))
        print("\(fixture.name) [\(language)]: skipped, crisis language — no model call")
        continue
    }

    guard let prompt = WeekReflectionService.promptText(from: fixture.logs, strings: strings, locale: locale) else {
        print("\(fixture.name) [\(language)]: no prompt (too thin)")
        continue
    }
    let instructions = WeekReflectionService.instructions(hasMood: WeekReflectionService.hasMood(in: fixture.logs),
                                                          dayCount: fixture.logs.count, strings: strings)
    for sample in 1...samples {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = WeekReflectionService.sanitize(response.content)
            runs.append(Run(fixture: fixture.name, language: language, sample: sample, skippedForCrisisLanguage: false,
                            prompt: prompt, instructions: instructions, output: text, error: nil))
        } catch {
            runs.append(Run(fixture: fixture.name, language: language, sample: sample, skippedForCrisisLanguage: false,
                            prompt: prompt, instructions: instructions, output: nil, error: String(describing: error)))
        }
    }
    print("\(fixture.name) [\(language)]: \(samples) samples done")
}

// MARK: - Report

let generated = runs.filter { !$0.skippedForCrisisLanguage }
let outputs = generated.compactMap(\.output)
let errors = generated.filter { $0.error != nil }
let markdown = outputs.filter(hasMarkdown)
let averageNumbers = outputs.isEmpty ? 0 : Double(outputs.map(numbers).reduce(0, +)) / Double(outputs.count)
// The unedited-metrics week must never produce a rating.
let unedited = generated.filter { $0.fixture == "D-unedited-metrics" }.compactMap(\.output)
let inventedRatings = unedited.filter(mentionsUnenteredRatings)
let crisisSkipped = runs.filter(\.skippedForCrisisLanguage).map(\.fixture)

print("""

=== Acceptance ===
runs:                 \(generated.count) generated, \(crisisSkipped.count) skipped for crisis language
errors:               \(errors.count)            (expected 0)
markdown in output:   \(markdown.count)          (expected 0)
numbers per output:   \(String(format: "%.1f", averageNumbers))          (expected <= 2.0)
sentence counts:      \(outputs.map(sentenceCount).sorted().map(String.init).joined(separator: ","))
invented ratings (D): \(inventedRatings.count)   (expected 0)
crisis fixtures:      \(crisisSkipped.joined(separator: ", "))
""")

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
try encoder.encode(runs).write(to: URL(fileURLWithPath: "runs.json"))
print("wrote runs.json (\(runs.count) records)")
