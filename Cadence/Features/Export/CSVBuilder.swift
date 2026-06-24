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

    private static let header = "Date,Mood,Energy,Sleep Hours,Stress,Symptoms,Factors"

    // Pure string form, kept separate from file I/O so it's unit-testable.
    static func csvString(from logs: [DailyLogSnapshot]) -> String {
        var rows = [header]
        for log in logs.sorted(by: { $0.date < $1.date }) {
            let fields = [
                dateFormatter.string(from: log.date),
                "\(log.mood)",
                "\(log.energy)",
                String(format: "%.1f", log.sleepHours),
                "\(log.stressLevel)",
                log.symptoms.map(\.name).joined(separator: "; "),
                log.factors.joined(separator: "; "),
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func build(logs: [DailyLogSnapshot]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-export-\(UUID().uuidString).csv")
        do {
            try csvString(from: logs).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // Quote fields containing a comma, quote, or newline; double embedded quotes.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
