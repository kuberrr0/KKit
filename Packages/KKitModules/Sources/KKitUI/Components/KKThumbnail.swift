import AppKit
import ImageIO
import SwiftUI

/// A downscaled image from a file, decoded off the main thread. Shows the file's
/// Finder icon for anything that isn't an image, and while loading.
public struct KKThumbnail: View {
    let url: URL?
    let maxPixelSize: CGFloat
    let contentMode: ContentMode

    @State private var loaded: LoadedImage?

    public init(url: URL?, maxPixelSize: CGFloat = 320, contentMode: ContentMode = .fit) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
    }

    public var body: some View {
        Group {
            if let loaded, loaded.url == url {
                Image(decorative: loaded.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.8)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            guard let url else { return }
            loaded = await Self.load(url, maxPixelSize: maxPixelSize)
        }
    }

    struct LoadedImage: @unchecked Sendable {
        let url: URL
        let image: CGImage
    }

    nonisolated static func load(_ url: URL, maxPixelSize: CGFloat) async -> LoadedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return LoadedImage(url: url, image: image)
    }
}

/// A colour swatch with a hairline border.
public struct KKSwatch: View {
    let color: Color
    let size: CGFloat

    public init(_ color: Color, size: CGFloat = 16) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }
}
