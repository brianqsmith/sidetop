import QuickLookThumbnailing
import SwiftUI

struct FileThumbnailView: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: size * 2, height: size * 2),
                                                   scale: 2,
                                                   representationTypes: [.thumbnail, .icon])
        thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

private extension QLThumbnailRepresentation {
    var nsImage: NSImage { NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)) }
}
