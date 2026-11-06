#if os(iOS)
import CoreLocation
import Foundation

enum LocationProblem: Error, Equatable {
    /// The app does not declare location use, or the device cannot locate.
    case unavailable
    case denied
    case timeout
    case failed
}

/// One location fix, high accuracy, 15 s at most. Permission is asked for
/// only here, when the subject taps "My location".
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?

    func current(timeout: Duration = .seconds(15)) async throws -> CLLocationCoordinate2D {
        guard continuation == nil else { throw LocationProblem.failed }
        // Without the usage string iOS ignores the request and nothing ever
        // comes back, so fail at once instead of waiting out the timeout.
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
            throw LocationProblem.unavailable
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .denied, .restricted:
                finish(.failure(LocationProblem.denied))
                return
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            default:
                manager.requestLocation()
            }
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish(.failure(LocationProblem.timeout))
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted: self.finish(.failure(LocationProblem.denied))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finish(.failure(denied ? LocationProblem.denied : LocationProblem.failed)) }
    }
}
#endif
