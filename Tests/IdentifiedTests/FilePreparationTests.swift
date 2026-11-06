import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Identified

private func png(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

@Test func imagesAreReencodedAsJPEGWithTheLongSideCapped() throws {
    let prepared = try FilePreparation.prepare(png(width: 3000, height: 1500), contentType: .png, maxBytes: 8 << 20)
    #expect(prepared.mimeType == "image/jpeg")
    let size = try #require(jpegSize(prepared.data))
    #expect(size.width == 2000 && size.height == 1000)
}

@Test func smallImagesAreNotEnlarged() throws {
    let prepared = try FilePreparation.prepare(png(width: 800, height: 600), contentType: .png, maxBytes: 8 << 20)
    #expect(jpegSize(prepared.data) == CGSize(width: 800, height: 600))
}

@Test func pdfsPassThrough() throws {
    let pdf = Data("%PDF-1.4\n".utf8)
    #expect(try FilePreparation.prepare(pdf, contentType: .pdf, maxBytes: 100) == PreparedFile(data: pdf, mimeType: "application/pdf"))
}

@Test func filesOverTheLimitAreRefusedOnTheDevice() {
    #expect(throws: FilePreparationError.tooLarge(megabytes: 1)) {
        try FilePreparation.prepare(Data(count: (1 << 20) + 1), contentType: .pdf, maxBytes: 1 << 20)
    }
}

@Test func anImageThatDoesNotDecodeIsUnreadable() {
    #expect(throws: FilePreparationError.unreadable) {
        try FilePreparation.prepare(Data("not a png".utf8), contentType: .png, maxBytes: 1 << 20)
    }
}
