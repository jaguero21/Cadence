import Foundation
import SwiftData

@Model
final class Medication {
    var name: String
    var dosage: String        // free text, e.g. "50 mg"
    var startDate: Date
    var endDate: Date?        // nil = ongoing
    var notes: String

    init(name: String, dosage: String = "", startDate: Date = .now, endDate: Date? = nil, notes: String = "") {
        self.name = name
        self.dosage = dosage
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.notes = notes
    }

    var isActive: Bool {
        guard let endDate else { return true }
        return endDate >= Calendar.current.startOfDay(for: .now)
    }

    var displayLabel: String {
        dosage.isEmpty ? name : "\(name) — \(dosage)"
    }
}

// Sendable projection for PatternEngine / PDF export, mirroring DailyLogSnapshot:
// @Model isn't Sendable, so snapshot before crossing isolation boundaries.
struct MedicationSnapshot: Sendable {
    let name: String
    let dosage: String
    let startDate: Date
    let endDate: Date?

    init(_ med: Medication) {
        name = med.name
        dosage = med.dosage
        startDate = med.startDate
        endDate = med.endDate
    }

    init(name: String, dosage: String = "", startDate: Date, endDate: Date? = nil) {
        self.name = name
        self.dosage = dosage
        self.startDate = startDate
        self.endDate = endDate
    }

    var displayLabel: String { dosage.isEmpty ? name : "\(name) — \(dosage)" }
}
