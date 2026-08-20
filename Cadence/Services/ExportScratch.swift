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
    // so a generated report can't be read off a locked device. (Without it the
    // default is completeUntilFirstUserAuthentication, which stays readable
    // whenever the device has been unlocked once since boot.)
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    // The ONE way an export reaches disk. Every generated file — report, CSV,
    // backup — goes through here rather than calling `Data.write` itself, so
    // the options above cannot be forgotten by a new export path.
    //
    // They were forgotten once: the PDF report, the most sensitive artefact of
    // the three, wrote itself through `UIGraphicsPDFRenderer.writePDF(to:)`,
    // which takes a URL and no write options at all. It picked up this
    // directory but none of its protection.
    //
    // Note for tests: the applied protection class is NOT observable in the
    // simulator — `attributesOfItem` reports `.protectionKey` as nil there even
    // for a file written with `.completeFileProtection` — so this is enforced
    // by having one code path, not by an assertion.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: writeOptions)
    }

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
