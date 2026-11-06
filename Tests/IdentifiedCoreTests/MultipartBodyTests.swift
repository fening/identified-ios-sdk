import Foundation
import Testing
@testable import IdentifiedCore

@Test func buildsFieldsAndAFileInOrder() {
    var body = MultipartBody(boundary: "B")
    body.addField("type", "selfie")
    body.addField("capture_role", "center")
    body.addFile("file", filename: "selfie.jpg", mimeType: "image/jpeg", data: Data("JPEG".utf8))
    let expected = "--B\r\nContent-Disposition: form-data; name=\"type\"\r\n\r\nselfie\r\n"
        + "--B\r\nContent-Disposition: form-data; name=\"capture_role\"\r\n\r\ncenter\r\n"
        + "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"selfie.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n"
        + "--B--\r\n"
    #expect(String(decoding: body.finalized(), as: UTF8.self) == expected)
    #expect(body.contentType == "multipart/form-data; boundary=B")
}

@Test func namesUploadsAfterTheirContent() {
    #expect(MultipartBody.uploadFilename(docType: "selfie", mimeType: "image/jpeg") == "selfie.jpg")
    #expect(MultipartBody.uploadFilename(docType: "proof_of_address", mimeType: "image/png") == "proof_of_address.png")
    #expect(MultipartBody.uploadFilename(docType: "proof_of_address", mimeType: "image/webp") == "proof_of_address.webp")
    #expect(MultipartBody.uploadFilename(docType: "proof_of_address", mimeType: "application/pdf") == "proof_of_address.pdf")
    #expect(MultipartBody.uploadFilename(docType: "license_front", mimeType: "application/octet-stream") == "license_front.jpg")
}

@Test func defaultBoundariesAreUnique() {
    #expect(MultipartBody().boundary != MultipartBody().boundary)
}
