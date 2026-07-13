import Foundation

enum AttachmentKind: String, Codable, Sendable {
    case photo
    case audio   // voice notes, recorded via AudioRecorder (VoiceNote.swift)
}

// A media attachment on a DailyLog. The binary lives on disk (see AttachmentStore);
// the log stores only this lightweight reference so SwiftData rows stay small.
struct Attachment: Codable, Sendable, Identifiable {
    // Which reflection card an attachment belongs to; nil = the general
    // one-line-note card. Optional so entries stored before the field existed
    // decode fine (they read as general).
    static let peaksAndValleysSection = "peaksAndValleys"
    static let intentionsSection = "intentions"

    var id: UUID
    var kind: AttachmentKind
    var filename: String
    var createdAt: Date
    var section: String?

    init(id: UUID = UUID(), kind: AttachmentKind, filename: String, createdAt: Date = .now, section: String? = nil) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.createdAt = createdAt
        self.section = section
    }
}
