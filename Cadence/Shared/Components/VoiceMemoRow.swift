import SwiftUI

// A single optional voice memo: record / re-record / play / delete. Used by
// both the daily log's and weekly review's "Peaks and Valleys" step. Distinct
// from the note step's multi-attachment list (AttachmentPhotoStrip territory)
// — this manages exactly one Attachment, not a collection.
struct VoiceMemoRow: View {
    @Binding var attachment: Attachment?
    var recorder: AudioRecorder
    let store: AttachmentStore
    // Callers own file-deletion policy for the attachment being replaced/removed
    // (e.g. LogInputFlow defers deleting a persisted file until save succeeds;
    // ReviewFlowView deletes immediately) — this view only manages the binding.
    var onReplace: (_ old: Attachment?, _ new: Attachment) -> Void = { _, _ in }
    var onDelete: (Attachment) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggleRecording()
            } label: {
                Label(
                    recorder.isRecording ? "Stop recording" : (attachment == nil ? "Record voice memo" : "Re-record"),
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.badge.plus"
                )
                .font(.subheadline)
                .foregroundStyle(recorder.isRecording ? CadenceColor.stressRed : CadenceColor.accent)
            }
            .buttonStyle(.plain)

            if let attachment, !recorder.isRecording {
                AudioPlaybackButton(url: store.url(for: attachment.filename))
                Button {
                    onDelete(attachment)
                    self.attachment = nil
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let url = recorder.stop(),
                  let data = try? Data(contentsOf: url),
                  let filename = store.save(data, fileExtension: "m4a") else { return }
            let new = Attachment(kind: .audio, filename: filename)
            onReplace(attachment, new)
            attachment = new
            try? FileManager.default.removeItem(at: url)
        } else {
            Task {
                guard await recorder.requestPermission() else { return }
                recorder.start()
            }
        }
    }
}
