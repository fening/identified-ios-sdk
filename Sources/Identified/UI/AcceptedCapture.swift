import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Display-only evidence for this flow. Never retains original upload bytes.
struct AcceptedCapture: Identifiable, Equatable {
    let docType: String
    let mimeType: String
    let thumbnail: Data?
    var id: String { docType }
    var isPDF: Bool { mimeType == "application/pdf" }

    static let maximumItems = 8
    static let maximumDimension = 320
    static let maximumThumbnailBytes = 96 * 1024

    init(docType: String, data: Data, mimeType: String) {
        self.docType = docType
        self.mimeType = mimeType
        thumbnail = mimeType == "application/pdf" ? nil : Self.makeThumbnail(data)
    }

    private static func makeThumbnail(_ data: Data) -> Data? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let longSide = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? maximumDimension,
                               properties?[kCGImagePropertyPixelHeight] as? Int ?? maximumDimension)
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(maximumDimension, longSide),
                    kCGImageSourceShouldCacheImmediately: false,
                  ] as CFDictionary) else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
            guard CGImageDestinationFinalize(destination), output.length <= maximumThumbnailBytes else { return nil }
            return output as Data
        }
    }
}
