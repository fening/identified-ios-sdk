import CoreImage
import IdentifiedCore
@preconcurrency import Vision

/// Vision face landmarks as a `FaceObservation` (ours, not Vision's Swift type of
/// the same name) in the frame's top-left
/// pixels. Pupils stand in for InsightFace's eye points, and the lowest point
/// of the nose crest for its nose tip.
final class FaceLandmarkDetector: @unchecked Sendable {
    func detect(in frame: CameraFrame) -> IdentifiedCore.FaceObservation? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: frame.image, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        guard
            let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
            let landmarks = face.landmarks,
            let firstPupil = landmarks.leftPupil,
            let secondPupil = landmarks.rightPupil,
            let noseCrest = landmarks.noseCrest
        else { return nil }

        let size = frame.size
        let imageSize = CGSize(width: size.width, height: size.height)
        // Vision's image points have a bottom-left origin.
        func topLeft(_ point: CGPoint) -> FacePoint { FacePoint(x: point.x, y: size.height - point.y) }
        guard
            let first = firstPupil.pointsInImage(imageSize: imageSize).first,
            let second = secondPupil.pointsInImage(imageSize: imageSize).first,
            let noseTip = noseCrest.pointsInImage(imageSize: imageSize).min(by: { $0.y < $1.y })
        else { return nil }

        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
        return IdentifiedCore.FaceObservation(
            box: PixelRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height),
            firstEye: topLeft(first),
            secondEye: topLeft(second),
            nose: topLeft(noseTip),
            headYawRadians: face.yaw?.doubleValue
        )
    }
}
