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
        let headerLine = ([header] + trackers.map { escape(neutralizeFormula(trackerColumnName($0))) }).joined(separator: ",")
        var rows = [headerLine]
        for log in logs.sorted(by: { $0.date < $1.date }) {
            // Unentered values are empty cells, the same convention as a
            // missing HealthKit measurement: an untouched mood or slider still
            // holds DailyLog's default, which isn't a reading.
            let m = log.didEditMetrics
            var fields: [String] = [
                dateFormatter.string(from: log.date),
                log.didEditMood ? "\(log.mood)" : "",
                m ? "\(log.energy)" : "",
                m ? String(format: "%.1f", log.sleepHours) : "",
                m ? "\(log.sleepQuality)" : "",
                m ? "\(log.painLevel)" : "",
                m ? "\(log.brainFogLevel)" : "",
                m ? "\(log.stressLevel)" : "",
            ]
            // Free text goes through neutralizeFormula: this file is often
            // opened in Excel by someone else (a clinician), and a note that
            // starts with "=" would otherwise run as a formula there.
            fields += [
                neutralizeFormula(log.symptoms.map(\.name).joined(separator: "; ")),
                neutralizeFormula(log.basicsCompleted.joined(separator: "; ")),
                neutralizeFormula(log.factors.joined(separator: "; ")),
                neutralizeFormula(log.peaksAndValleysNote),
                log.hasPeaksAndValleysVoiceMemo ? "Yes" : "No",
                neutralizeFormula(log.intentionsForTomorrow),
                neutralizeFormula(log.freeNote),
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

    static func build(logs: [DailyLogSnapshot], trackers: [CustomTrackerSnapshot] = [], range: ClosedRange<Date>? = nil) -> URL? {
        let url = ExportScratch.uniqueURL(named: PDFBuilder.fileName(range: range ?? PDFBuilder.logSpan(logs),
                                                                     prefix: "Cadence Data", ext: "csv"))
        do {
            // Written as Data so the file gets ExportScratch's protection
            // options; String.write(to:atomically:) offers no equivalent.
            // The UTF-8 byte-order mark is what makes Excel read the file as
            // UTF-8; without it "Sueño" or an emoji in a note came out garbled.
            // Numbers and Google Sheets ignore it.
            guard let data = (byteOrderMark + csvString(from: logs, trackers: trackers)).data(using: .utf8) else { return nil }
            try ExportScratch.write(data, to: url)
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
    static let byteOrderMark = "\u{FEFF}"

    // Spreadsheet apps evaluate a cell starting with = + - @ (or a tab/CR)
    // as a formula. A leading apostrophe makes it plain text and is hidden by
    // Excel. Only applied to free text — numeric cells stay numeric.
    // Pure and unit-tested.
    nonisolated static func neutralizeFormula(_ field: String) -> String {
        guard let first = field.first, "=+-@\t\r".contains(first) else { return field }
        return "'" + field
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
