import Foundation
import ImageIO
import IdentifiedCore
import UniformTypeIdentifiers

struct PreparedFile: Equatable, Sendable {
    let data: Data
    let mimeType: String
}

enum FilePreparationError: Error, Equatable {
    case tooLarge(megabytes: Int)
    /// "We could not read that file on this device."
    case unreadable
    /// "That file could not be prepared."
    case failed
}

/// `frontend/src/lib/imageNormalise.ts`: a chosen image becomes a JPEG at 0.9
/// with its long side at most 2000 px, upright; a PDF goes as it is. The size
/// limit is checked on the original, as the web checks the file it was given.
enum FilePreparation {
    static let maxSide = 2000

    static func prepare(_ data: Data, contentType: UTType, maxBytes: Int) throws -> PreparedFile {
        guard data.count <= maxBytes else {
            throw FilePreparationError.tooLarge(megabytes: Int((Double(maxBytes) / Double(1 << 20)).rounded()))
        }
        if contentType.conforms(to: .pdf) {
            return PreparedFile(data: data, mimeType: "application/pdf")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw FilePreparationError.unreadable
        }
        // The thumbnail API scales to its max size, up as well as down, so
        // ask for no more than the image already has.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longSide = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? maxSide, properties?[kCGImagePropertyPixelHeight] as? Int ?? maxSide)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxSide, longSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FilePreparationError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FilePreparationError.failed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FilePreparationError.failed }
        return PreparedFile(data: output as Data, mimeType: "image/jpeg")
    }
}
