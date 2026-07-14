import Foundation
import SwiftData

@Model
final class Medication {
    var name: String = ""
    var dosage: String = ""        // free text, e.g. "50 mg"
    var startDate: Date = Calendar.current.startOfDay(for: .now)
    var endDate: Date?             // nil = ongoing
    var notes: String = ""
    // Daily reminder times as minutes since midnight (e.g. 540 = 9:00 am);
    // empty = no reminders. Minutes-not-Dates so the times are calendar-day
    // anchored and CloudKit-friendly (inline default, plain value array).
    var reminderMinutes: [Int] = []

    init(name: String, dosage: String = "", startDate: Date = .now, endDate: Date? = nil, notes: String = "", reminderMinutes: [Int] = []) {
        self.name = name
        self.dosage = dosage
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.notes = notes
        self.reminderMinutes = reminderMinutes
    }

    var isActive: Bool {
        guard let endDate else { return true }
        return endDate >= Calendar.current.startOfDay(for: .now)
    }

    var displayLabel: String {
        dosage.isEmpty ? name : "\(name) — \(dosage)"
    }

    // Minutes-since-midnight ↔ picker Date conversions (pure, unit-tested).
    static func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func timeToday(fromMinute minute: Int) -> Date {
        Calendar.current.date(bySettingHour: (minute / 60) % 24, minute: minute % 60, second: 0, of: .now) ?? .now
    }
}

// Sendable projection for PatternEngine / PDF export, mirroring DailyLogSnapshot:
// @Model isn't Sendable, so snapshot before crossing isolation boundaries.
struct MedicationSnapshot: Sendable {
    let name: String
    let dosage: String
    let startDate: Date
    let endDate: Date?
    let reminderMinutes: [Int]

    init(_ med: Medication) {
        name = med.name
        dosage = med.dosage
        startDate = med.startDate
        endDate = med.endDate
        reminderMinutes = med.reminderMinutes
    }

    init(name: String, dosage: String = "", startDate: Date, endDate: Date? = nil, reminderMinutes: [Int] = []) {
        self.name = name
        self.dosage = dosage
        self.startDate = startDate
        self.endDate = endDate
        self.reminderMinutes = reminderMinutes
    }

    var displayLabel: String { dosage.isEmpty ? name : "\(name) — \(dosage)" }

    // Mirrors Medication.isActive: an end date today or later still counts.
    var isActive: Bool {
        guard let endDate else { return true }
        return endDate >= Calendar.current.startOfDay(for: .now)
    }
}
