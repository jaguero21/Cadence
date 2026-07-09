import Foundation
import UIKit
import ImageIO
import OSLog

// Stores attachment binaries as files under a directory (Documents/Attachments
// by default), so SwiftData only holds lightweight Attachment references. The
// base directory is injectable so it can be exercised against a temp dir in
// tests. Directory creation is deferred to save() — reads don't need it, and
// this struct is re-initialized on every render of the views that hold it.
struct AttachmentStore {
    private static let log = Logger(subsystem: "com.carpecadence", category: "AttachmentStore")
    let baseURL: URL

    init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseURL = docs.appendingPathComponent("Attachments", isDirectory: true)
        }
    }

    func url(for filename: String) -> URL {
        baseURL.appendingPathComponent(filename)
    }

    // Writes data with a fresh unique filename and returns that filename (nil on failure).
    func save(_ data: Data, fileExtension: String) -> String? {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).\(fileExtension)"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            Self.log.error("Failed to write attachment \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    func data(for filename: String) -> Data? {
        try? Data(contentsOf: url(for: filename))
    }

    // Decodes a thumbnail at the requested pixel size via ImageIO, so callers
    // never hold a full-resolution bitmap just to show a 64pt tile.
    func thumbnail(for filename: String, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url(for: filename) as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
