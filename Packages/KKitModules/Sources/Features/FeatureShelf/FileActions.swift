import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// The formats "Convert Image" writes. ImageIO can read WebP but not write it.
enum ShelfImageFormat: String, Sendable, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }
}

/// File work for Shelf items. Everything here is synchronous and runs off the main actor.
enum FileActions {
    /// `name.ext`, `name 2.ext`, … in `folder`, like Finder's duplicates.
    static func available(_ name: String, extension ext: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let file = ext.isEmpty ? name : "\(name).\(ext)"
        var candidate = folder.appendingPathComponent(file)
        var counter = 2
        while exists(candidate) {
            let numbered = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    /// The new file name for a rename: keeps the extension if the user left it off.
    static func renamedFileName(_ proposed: String, original: URL) -> String? {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("."), !trimmed.contains("/"), !trimmed.contains(":") else { return nil }
        let ext = original.pathExtension
        if ext.isEmpty || (trimmed as NSString).pathExtension.lowercased() == ext.lowercased() {
            return trimmed
        }
        return "\(trimmed).\(ext)"
    }

    /// Copies `source` into a new folder of its own under `folder`, keeping its name.
    static func copyIn(_ source: URL, to folder: URL) throws -> URL {
        let holder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
        let destination = holder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Writes image data from a drop into a new file under `folder`.
    static func writeImage(_ data: Data, type: String, to folder: URL, name: String = "Image") throws -> URL {
        let holder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
        let ext = UTType(type)?.preferredFilenameExtension ?? "png"
        let url = holder.appendingPathComponent("\(name).\(ext)")
        try data.write(to: url)
        return url
    }

    /// Zips a file or folder next to it (or into `folder`): `name.zip`.
    static func compress(_ source: URL, into folder: URL) throws -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        let destination = available(name, extension: "zip", in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ShelfError.failed(message.isEmpty ? String(localized: "Couldn't compress “\(source.lastPathComponent)”.") : message)
        }
        return destination
    }

    /// Converts an image to `format`, optionally scaling it so its longer side is at most
    /// `maxPixels`. Writes next to it (or into `folder`).
    static func convertImage(_ source: URL, to format: ShelfImageFormat, maxPixels: Int?, into folder: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw ShelfError.notAnImage }
        let image: CGImage?
        if let maxPixels {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }
        guard let image else { throw ShelfError.notAnImage }
        var name = source.deletingPathExtension().lastPathComponent
        if maxPixels != nil {
            name += " (\(image.width)×\(image.height))"
        }
        let destination = available(name, extension: format.fileExtension, in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ShelfError.failed(String(localized: "Couldn't write \(format.title)."))
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw ShelfError.failed(String(localized: "Couldn't write \(format.title)."))
        }
        return destination
    }

    /// Half the longer side, for "Resize to half".
    static func halfSize(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(max(width, height) / 2, 1)
    }

    /// One PDF with every page of `sources`, in order.
    static func mergePDFs(_ sources: [URL], into folder: URL) throws -> URL {
        guard sources.count >= 2 else { throw ShelfError.needsTwoPDFs }
        let merged = PDFDocument()
        for source in sources {
            guard let document = PDFDocument(url: source) else {
                throw ShelfError.failed(String(localized: "Couldn't open “\(source.lastPathComponent)”."))
            }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let destination = available(String(localized: "Merged"), extension: "pdf", in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        guard merged.write(to: destination) else {
            throw ShelfError.failed(String(localized: "Couldn't write the merged PDF."))
        }
        return destination
    }
}
