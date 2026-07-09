import Foundation

enum AttachmentKind: String, Codable, Sendable {
    case photo
    case audio   // voice notes, recorded via AudioRecorder (VoiceNote.swift)
}

// A media attachment on a DailyLog. The binary lives on disk (see AttachmentStore);
// the log stores only this lightweight reference so SwiftData rows stay small.
struct Attachment: Codable, Sendable, Identifiable {
    var id: UUID
    var kind: AttachmentKind
    var filename: String
    var createdAt: Date

    init(id: UUID = UUID(), kind: AttachmentKind, filename: String, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.createdAt = createdAt
    }
}
