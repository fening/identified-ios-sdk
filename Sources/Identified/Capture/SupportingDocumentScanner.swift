@preconcurrency import CoreImage
import IdentifiedCore
import Vision

/// Page geometry in Vision's normalized bottom-left coordinates, relative to
/// the visible image. The still gets its own detection in its own pixel space.
struct DocumentPage: Equatable, Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var area: CGFloat {
        let points = corners
        let next = points.dropFirst() + points.prefix(1)
        return abs(zip(points, next).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }) / 2
    }

    func matches(_ other: DocumentPage, tolerance: CGFloat) -> Bool {
        zip(corners, other.corners).allSatisfy { lhs, rhs in
            abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
        }
    }

    var isFullyInView: Bool {
        area >= 0.26 && corners.allSatisfy {
            (0.035...0.965).contains($0.x) && (0.035...0.965).contains($0.y)
        }
    }

    func straighten(_ image: CIImage) -> CIImage {
        let extent = image.extent
        func vector(_ point: CGPoint) -> CIVector {
            CIVector(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
        }
        return image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(topLeft), "inputTopRight": vector(topRight),
            "inputBottomRight": vector(bottomRight), "inputBottomLeft": vector(bottomLeft),
        ])
    }
}

struct SupportingDocumentScanner {
    private let renderer: FrameRenderer

    init(renderer: FrameRenderer) {
        self.renderer = renderer
    }

    func analysisImage(_ image: CIImage) -> CIImage? {
        guard let scaled = Self.scaled(image, maxEdge: 640),
              let raster = renderer.rasterize(scaled) else { return nil }
        return CIImage(cgImage: raster)
    }

    func detect(in image: CIImage) -> DocumentPage? {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.35
        request.minimumAspectRatio = 0.42
        request.quadratureTolerance = 25
        request.minimumConfidence = 0.75
        request.maximumObservations = 4
        do {
            try VNImageRequestHandler(ciImage: image).perform([request])
        } catch {
            return nil
        }
        let pages = (request.results ?? []).map {
            DocumentPage(topLeft: $0.topLeft, topRight: $0.topRight, bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft)
        }.filter(\.isFullyInView).sorted { $0.area > $1.area }
        guard let page = pages.first,
              !pages.dropFirst().contains(where: { $0.area >= page.area * 0.7 && !$0.matches(page, tolerance: 0.04) }) else { return nil }
        return page
    }

    func assess(_ image: CIImage) -> DocumentQuality? {
        guard let scaled = Self.scaled(image, maxEdge: 360) else { return nil }
        let width = Int(scaled.extent.width.rounded())
        let height = Int(scaled.extent.height.rounded())
        guard width >= 16, height >= 16,
              let pixels = renderer.analysisFrame(from: CameraFrame(image: scaled),
                  visible: PixelRect(x: 0, y: 0, width: scaled.extent.width, height: scaled.extent.height),
                  width: width, height: height) else { return nil }
        return DocumentQuality.assess(pixels)
    }

    func correctedJPEG(from image: CIImage, page: DocumentPage) -> Data? {
        let corrected = page.straighten(image)
        guard let bounded = Self.scaled(corrected, maxEdge: 4096) else { return nil }
        return renderer.jpeg(from: bounded, quality: 0.95)
    }

    private static func scaled(_ image: CIImage, maxEdge: CGFloat) -> CIImage? {
        let extent = image.extent
        let edge = max(extent.width, extent.height)
        guard edge.isFinite, min(extent.width, extent.height) >= 1 else { return nil }
        let scale = min(1, maxEdge / edge)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

struct DocumentPageHold {
    private static let tolerance: CGFloat = 0.018
    private var anchor: DocumentPage?
    private var previous: DocumentPage?
    private var startedAt: TimeInterval = 0
    private var lastSeen: TimeInterval = 0
    private var samples = 0
    private var fired = false

    mutating func observe(_ page: DocumentPage?, at now: TimeInterval) -> Bool {
        guard !fired else { return false }
        guard let page else {
            self = DocumentPageHold()
            return false
        }
        defer {
            previous = page
            lastSeen = now
        }
        guard let anchor, let previous, now - lastSeen <= 0.5,
              anchor.matches(page, tolerance: Self.tolerance),
              previous.matches(page, tolerance: Self.tolerance) else {
            anchor = page
            startedAt = now
            samples = 1
            return false
        }
        samples += 1
        fired = samples >= 5 && now - startedAt >= 0.75
        return fired
    }
}
