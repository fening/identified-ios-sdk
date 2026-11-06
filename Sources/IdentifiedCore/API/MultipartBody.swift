import Foundation

/// A `multipart/form-data` body built in memory. Captured images never touch
/// disk, so the body is assembled as `Data` rather than streamed from a file.
package struct MultipartBody: Sendable {
    package let boundary: String
    private var data = Data()

    package init(boundary: String = "identified-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    package var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    package mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    package mutating func addFile(_ name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    package func finalized() -> Data {
        var closed = data
        closed.append(Data("--\(boundary)--\r\n".utf8))
        return closed
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }

    private static let extensions = [
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/webp": "webp",
        "application/pdf": "pdf",
    ]

    /// `<docType>.<ext>`, named after the bytes it carries.
    package static func uploadFilename(docType: String, mimeType: String) -> String {
        "\(docType).\(extensions[mimeType] ?? "jpg")"
    }
}
