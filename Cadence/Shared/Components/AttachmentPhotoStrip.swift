import SwiftUI

// Horizontal strip of photo-attachment thumbnails, shared by the log flow
// (with delete) and the read-only log detail. Thumbnails are decoded once per
// attachment via AttachmentStore.thumbnail — downsampled at decode time in a
// .task — so scrolling/typing in the host view never re-reads or re-decodes
// full-resolution images in body.
struct AttachmentPhotoStrip: View {
    let photos: [Attachment]
    let store: AttachmentStore
    var tileSize: CGFloat = 64
    var onDelete: ((Attachment) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    AttachmentThumbnail(store: store, filename: photo.filename, tileSize: tileSize)
                        .overlay(alignment: .topTrailing) {
                            if let onDelete {
                                Button {
                                    onDelete(photo)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(2)
                                .accessibilityLabel("Remove photo")
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct AttachmentThumbnail: View {
    let store: AttachmentStore
    let filename: String
    let tileSize: CGFloat
    @State private var image: UIImage?
    // nil while the decode is still in flight; true once it has run and come
    // back empty. Distinguishing the two is what lets the missing-file case
    // show an explanation instead of an indefinite blank tile.
    @State private var isMissing = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isMissing {
                // The Attachment record synced via CloudKit but its binary did
                // not — binaries live on disk (AttachmentStore) and are
                // deliberately excluded from both the synced store and the JSON
                // backup. Without this the tile is simply blank, which reads as
                // data loss rather than a device-local file.
                ZStack {
                    Rectangle().fill(Color(.systemFill))
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: tileSize * 0.34))
                        .foregroundStyle(.secondary)
                }
            } else {
                Rectangle().fill(Color(.systemFill))
            }
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(isMissing ? "Photo added on another device — not available here" : "Attached photo")
        .task(id: filename) {
            let decoded = store.thumbnail(for: filename, maxPixel: tileSize * displayScale)
            image = decoded
            isMissing = decoded == nil
        }
    }
}
