import Foundation

// Stores attachment binaries as files under a directory (Documents/Attachments by
// default), so SwiftData only holds lightweight Attachment references. The base
// directory is injectable so it can be exercised against a temp dir in tests.
struct AttachmentStore {
    let baseURL: URL

    init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseURL = docs.appendingPathComponent("Attachments", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseURL, withIntermediateDirectories: true)
    }

    func url(for filename: String) -> URL {
        baseURL.appendingPathComponent(filename)
    }

    // Writes data with a fresh unique filename and returns that filename (nil on failure).
    func save(_ data: Data, fileExtension: String) -> String? {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    func data(for filename: String) -> Data? {
        try? Data(contentsOf: url(for: filename))
    }

    func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
