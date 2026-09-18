import Foundation
import SwiftData

@Model
final class SymptomTag {
    var name: String = ""
    var emoji: String = ""
    var isDefault: Bool = false
    var sortOrder: Int = 0

    init(name: String, emoji: String, isDefault: Bool = false, sortOrder: Int = 0) {
        self.name = name
        self.emoji = emoji
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    // The seeded defaults, as plain values. This used to be a `static let` array
    // of @Model INSTANCES: one process-wide set of objects that seeding inserted
    // into a context, and that HealthKitService then read `.emoji` from off the
    // main actor. Never hold @Model instances in a static; readers take the
    // seeds, and seeding builds fresh models with makeDefaults(). Array order is
    // the seeded sortOrder.
    static let defaultSeeds: [(name: String, emoji: String)] = [
        ("Headache",  "🤕"),
        ("Fatigue",   "😴"),
        ("Anxiety",   "😰"),
        ("Brain Fog", "🌫️"),
        ("Pain",      "⚡️"),
    ]

    static func makeDefaults() -> [SymptomTag] {
        defaultSeeds.enumerated().map { index, seed in
            SymptomTag(name: seed.name, emoji: seed.emoji, isDefault: true, sortOrder: index)
        }
    }

    // The optional symptom library, toggleable in Settings → Symptoms. Every
    // name here resolves to a HealthKit symptom type (pinned by a unit test),
    // so an enabled symptom syncs both ways with Health. Kept separate from
    // `defaultSeeds` — these are opt-in, not seeded.
    static let optionalCatalog: [(name: String, emoji: String)] = [
        ("Nausea",                  "🤢"),
        ("Vomiting",                "🤮"),
        ("Dizziness",               "💫"),
        ("Fainting",                "😵"),
        ("Fever",                   "🌡️"),
        ("Chills",                  "🥶"),
        ("Coughing",                "😷"),
        ("Sore throat",             "🗣️"),
        ("Runny nose",              "🤧"),
        ("Sinus congestion",        "😤"),
        ("Shortness of breath",     "🫁"),
        ("Wheezing",                "💨"),
        ("Chest tightness or pain", "💔"),
        ("Racing heartbeat",        "💓"),
        ("Skipped heartbeat",       "💗"),
        ("Heartburn",               "🔥"),
        ("Bloating",                "🎈"),
        ("Abdominal cramps",        "🌀"),
        ("Constipation",            "🪨"),
        ("Diarrhea",                "💧"),
        ("Lower back pain",         "🦴"),
        ("Pelvic pain",             "🔻"),
        ("Breast pain",             "🩷"),
        ("Hot flashes",             "🥵"),
        ("Night sweats",            "💦"),
        ("Mood changes",            "🎭"),
        ("Memory lapse",            "💭"),
        ("Dry skin",                "🧴"),
        ("Acne",                    "🔴"),
        ("Hair loss",               "💇"),
        ("Bladder incontinence",    "🚾"),
        ("Vaginal dryness",         "🌸"),
        ("Loss of smell",           "👃"),
        ("Loss of taste",           "👅"),
    ]
}

struct Prompt: Codable, Identifiable {
    var id: UUID = UUID()
    var section: String
    var question: String
    var placeholder: String
    var isDefault: Bool = true

    static let weeklyDefaults: [Prompt] = [
        Prompt(section: "Week at a Glance",     question: "How was your week overall?",                              placeholder: "Reflect on the week as a whole…"),
        Prompt(section: "Wins This Week",        question: "What went well this week?",                               placeholder: "Big or small — write them all…"),
        Prompt(section: "What Didn't Work",      question: "What could have gone better?",                            placeholder: "Be honest, not harsh…"),
        Prompt(section: "Energy Audit",          question: "What gave you energy? What drained it?",                  placeholder: "People, tasks, environments…"),
        Prompt(section: "Goal Check-In",         question: "Did you follow through on last week's intentions?",        placeholder: "What happened and why…"),
        Prompt(section: "Body Check",            question: "Any patterns in how your body felt this week?",            placeholder: "Symptoms, energy, sleep patterns…"),
        Prompt(section: "Next Week Intentions",  question: "What are your 3 focus areas next week?",                  placeholder: "Keep it to three…"),
    ]
}
