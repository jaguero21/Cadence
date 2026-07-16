import Foundation

// Builds a spreadsheet-friendly CSV of daily logs. One row per logged day,
// using the fields carried on DailyLogSnapshot.
enum CSVBuilder {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let header = "Date,Mood,Energy,Sleep Hours,Sleep Quality,Pain,Brain Fog,Anxiety,Symptoms,Basics,Factors,Peaks and Valleys,Peaks and Valleys Voice Memo,Intentions for Tomorrow,Note,HK Steps,HK Resting HR,HK HRV,HK Sleep Hours,HK Active Energy,HK Mindful Minutes,HK Wrist Temp,HK Respiratory Rate,HK Blood Oxygen,HK Daylight Minutes,HK Daytime HR,HK Workout Minutes"

    // Pure string form, kept separate from file I/O so it's unit-testable.
    // Every user-entered and HealthKit field gets a column (media binaries and
    // bookkeeping flags excluded); optional HealthKit cells are empty when the
    // day has no measurement. One column per custom tracker is appended after
    // the HealthKit columns, in the caller's tracker order; a day without an
    // entry for that tracker gets an empty cell.
    static func csvString(from logs: [DailyLogSnapshot], trackers: [CustomTrackerSnapshot] = []) -> String {
        let headerLine = ([header] + trackers.map { escape(trackerColumnName($0)) }).joined(separator: ",")
        var rows = [headerLine]
        for log in logs.sorted(by: { $0.date < $1.date }) {
            var fields: [String] = [
                dateFormatter.string(from: log.date),
                "\(log.mood)",
                "\(log.energy)",
                String(format: "%.1f", log.sleepHours),
                "\(log.sleepQuality)",
                "\(log.painLevel)",
                "\(log.brainFogLevel)",
                "\(log.stressLevel)",
            ]
            fields += [
                log.symptoms.map(\.name).joined(separator: "; "),
                log.basicsCompleted.joined(separator: "; "),
                log.factors.joined(separator: "; "),
                log.peaksAndValleysNote,
                log.hasPeaksAndValleysVoiceMemo ? "Yes" : "No",
                log.intentionsForTomorrow,
                log.freeNote,
            ]
            // Appended one at a time with an explicit helper — a combined array
            // literal of optional-map + format expressions blows the compiler's
            // type-checking budget on slower machines (seen on the CI runner).
            fields.append(log.hkSteps.map(String.init) ?? "")
            fields.append(formatted(log.hkRestingHR, "%.0f"))
            fields.append(formatted(log.hkHRV, "%.0f"))
            fields.append(formatted(log.hkSleepHours, "%.1f"))
            fields.append(formatted(log.hkActiveEnergy, "%.0f"))
            fields.append(formatted(log.hkMindfulMinutes, "%.0f"))
            fields.append(formatted(log.hkWristTemp, "%.1f"))
            fields.append(formatted(log.hkRespiratoryRate, "%.1f"))
            fields.append(formatted(log.hkBloodOxygen, "%.0f"))
            fields.append(formatted(log.hkDaylightMinutes, "%.0f"))
            fields.append(formatted(log.hkDaytimeHR, "%.0f"))
            fields.append(formatted(log.hkWorkoutMinutes, "%.0f"))
            for tracker in trackers {
                let entry = log.customMetrics.first { $0.trackerID == tracker.id }
                fields.append(entry.map { String($0.value) } ?? "")
            }
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func build(logs: [DailyLogSnapshot], trackers: [CustomTrackerSnapshot] = []) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-export-\(UUID().uuidString).csv")
        do {
            try csvString(from: logs, trackers: trackers).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // An optional metric's CSV cell: formatted when present, empty when not.
    private static func formatted(_ value: Double?, _ format: String) -> String {
        guard let value else { return "" }
        return String(format: format, value)
    }

    // Header column for a custom tracker: name, plus unit in parens when set.
    private static func trackerColumnName(_ tracker: CustomTrackerSnapshot) -> String {
        tracker.unit.isEmpty ? tracker.name : "\(tracker.name) (\(tracker.unit))"
    }

    // Quote fields containing a comma, quote, or newline; double embedded quotes.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
