import Foundation

#if !SWIFT_PACKAGE
// SwiftPM synthesizes `Bundle.module`. CocoaPods does not, so the pod build provides the same
// accessor, pointing at the `IdentifiedResources` bundle declared in Identified.podspec.
private final class PodBundleToken {}

extension Bundle {
    static var module: Bundle {
        let host = Bundle(for: PodBundleToken.self)
        if let url = host.url(forResource: "IdentifiedResources", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return host
    }
}
#endif
