import Foundation
import OSLog

// Scratch space for generated exports (PDF reports, CSV, JSON backups).
//
// These files are the single most sensitive artefact the app produces — a full
// health history in plain text — and they used to be written straight into
// `FileManager.default.temporaryDirectory` with a fresh unique filename every
// time and never deleted. Generating a handful of reports left several complete
// copies sitting on disk until iOS decided to reclaim the space.
//
// Two changes: everything lands in one dedicated subdirectory that can be swept,
// and each file is written with complete protection so it is unreadable while
// the device is locked. `purge()` runs at launch — not after each share, since
// the share sheet hands the URL to another process and deleting underneath it
// would break AirDrop/Mail mid-transfer.
enum ExportScratch {
    private static let log = Logger(subsystem: "com.carpecadence", category: "ExportScratch")

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    // A URL for a new export, with the containing directory created. Callers
    // still choose the filename so report/CSV/backup naming stays theirs.
    static func url(for filename: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(filename)
    }

    // Write options every export should use: atomic, plus complete protection
    // so a generated report can't be read off a locked device.
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    // Deletes the whole scratch directory. Safe to call when it doesn't exist.
    static func purge() {
        let directory = self.directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            // Best effort: failing to clear scratch is never worth blocking
            // launch over, and the next purge will try again.
            log.error("Failed to purge export scratch: \(error, privacy: .public)")
        }
    }
}
