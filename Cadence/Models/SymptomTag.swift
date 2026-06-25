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

    static let defaults: [SymptomTag] = [
        SymptomTag(name: "Headache",  emoji: "🤕", isDefault: true, sortOrder: 0),
        SymptomTag(name: "Fatigue",   emoji: "😴", isDefault: true, sortOrder: 1),
        SymptomTag(name: "Anxiety",   emoji: "😰", isDefault: true, sortOrder: 2),
        SymptomTag(name: "Brain Fog", emoji: "🌫️", isDefault: true, sortOrder: 3),
        SymptomTag(name: "Pain",      emoji: "⚡️", isDefault: true, sortOrder: 4),
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
