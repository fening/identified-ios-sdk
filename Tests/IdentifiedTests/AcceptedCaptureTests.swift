import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Identified
import IdentifiedCore
import IdentifiedTestSupport

private func capturePNG(width: Int = 1200, height: Int = 800) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

@Test func acceptedThumbnailIsBoundedJPEGAndPDFKeepsNoEvidenceBytes() throws {
    let original = capturePNG()
    let item = AcceptedCapture(docType: DocType.licenseFront, data: original, mimeType: "image/png")
    let thumbnail = try #require(item.thumbnail)
    #expect(thumbnail != original)
    #expect(thumbnail.count <= AcceptedCapture.maximumThumbnailBytes)
    let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) == 320)
    let pdf = AcceptedCapture(docType: DocType.proofOfAddress, data: Data("%PDF-sensitive".utf8), mimeType: "application/pdf")
    #expect(pdf.isPDF)
    #expect(pdf.thumbnail == nil)
    let small = AcceptedCapture(docType: DocType.licenseBack, data: capturePNG(width: 80, height: 60), mimeType: "image/png")
    let smallThumbnailData = try #require(small.thumbnail)
    let smallSource = try #require(CGImageSourceCreateWithData(smallThumbnailData as CFData, nil))
    let smallImage = try #require(CGImageSourceCreateImageAtIndex(smallSource, 0, nil))
    #expect(smallImage.width == 80 && smallImage.height == 60)
}

@MainActor @Test func onlyAcceptedUploadsAppearAndReplacementKeepsOneTile() async throws {
    let transport = StubTransport(
        .data(Fixtures.sessionJSON(["case_id": "case-1"])),
        .json(200, ["success": true]), .error(422, "not readable"), .json(200, ["success": true])
    )
    let model = FlowModel(client: client(transport)) { _ in }
    await model.load()
    #expect(model.capturedItems.isEmpty)
    let bytes = capturePNG()
    try await model.upload(docType: DocType.licenseFront, data: bytes, mimeType: "image/png")
    #expect(model.capturedItems.count == 1)
    #expect(transport.requests[1].httpBody?.range(of: bytes) != nil)
    do {
        try await model.upload(docType: DocType.licenseBack, data: bytes, mimeType: "image/png")
        Issue.record("A refused upload unexpectedly succeeded")
    } catch { }
    #expect(model.capturedItems.map(\.docType) == [DocType.licenseFront])
    try await model.upload(docType: DocType.licenseFront, data: capturePNG(width: 600, height: 800), mimeType: "image/png")
    #expect(model.capturedItems.count == 1)
    model.path = [.checklist, .review]
    #expect(model.capturedItems.count == 1)
    model.close()
    #expect(model.capturedItems.isEmpty)
}

@MainActor @Test func sideSelfiesNeverReplaceTheCentreThumbnailAndStoreHasACap() async throws {
    let transport = StubTransport(.data(Fixtures.sessionJSON(["case_id": "case-1"])))
    transport.enqueue(Array(repeating: .json(200, ["success": true]), count: AcceptedCapture.maximumItems + 5))
    let model = FlowModel(client: client(transport)) { _ in }
    await model.load()
    let bytes = capturePNG(width: 80, height: 60)
    try await model.upload(docType: DocType.selfie, captureRole: SelfieRole.left, data: bytes, mimeType: "image/png")
    #expect(model.capturedItems.isEmpty)
    try await model.upload(docType: DocType.selfie, captureRole: SelfieRole.center, data: bytes, mimeType: "image/png")
    let centre = model.capturedItems
    try await model.upload(docType: DocType.selfie, captureRole: SelfieRole.right, data: bytes, mimeType: "image/png")
    #expect(model.capturedItems == centre)
    for index in 0...AcceptedCapture.maximumItems {
        try await model.upload(docType: "document-\(index)", data: Data("%PDF".utf8), mimeType: "application/pdf")
    }
    #expect(model.capturedItems.count == AcceptedCapture.maximumItems)
}
