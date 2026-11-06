# Identified iOS SDK

Native identity verification flow for iOS 16+: consent, name, ID details, ID
front and back, three-pose selfie, review and status. UIKit and SwiftUI entry
points. See `../README.md` for integration and `../../docs/mobile-sdk-review-2026-11-03.md`
for the review findings.

## Install (Swift Package Manager)

In Xcode choose **File > Add Package Dependencies** and enter
`https://github.com/fening/identified-ios-sdk`, version **0.1.0** or newer. Or in
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fening/identified-ios-sdk", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Identified", package: "identified-ios-sdk"),
    ]),
]
```

Then `import Identified`. Your app's `Info.plist` needs
`NSCameraUsageDescription`.

## Validation status

**Proven on hardware:** the full flow ran on a physical iPhone 12 against the
production API on 2026-11-06 (consent through upload and the status screen). Only
that one device and iOS version were tested, and server-side check results were
not inspected in that run. Android has no physical-device run on record.

## License

MIT, see `LICENSE`. The bundled DM Sans and Outfit fonts are under the SIL Open
Font License; their notices are in `Sources/Identified/Resources/Fonts`.

## Layout

- `Sources/IdentifiedCore`: models, API client, flow engine. Foundation only,
  `package` access, invisible to host apps.
- `Sources/IdentifiedCore/Capture`: ports of the web's capture algorithms
  (`cardAutoCapture.ts`, `documentQuality.ts`, `FluidTurnChallenge.tsx`), on
  plain pixel buffers and landmarks with time passed in.
- `Example`: a SwiftUI app that presents the flow for a pasted token. Open
  `Example/IdentifiedExample.xcodeproj`.
- `Sources/Identified`: the public product, plus the camera, Vision and Core
  Image glue in `Capture/`. `CameraController` is iOS-only; everything else
  also builds on macOS so `swift test` covers it.

## Tests

```bash
swift test
```

Runs on macOS. The live smoke test is skipped in the ordinary suite. For the
existing local Docker stack, use the shared runner from the repository root:

```bash
python3 mobile/scripts/local_backend_smoke.py --platform ios
# Or exercise both clients against fresh sessions:
python3 mobile/scripts/local_backend_smoke.py --platform both
```

The runner creates an isolated synthetic test tenant, supplies fresh in-memory
session credentials, records consent, saves synthetic metadata, and verifies
case reads/resume. It deletes its own fixture and verifies cleanup. No images,
provider checks, delivery or billing calls are made. See `../scripts/README.md`.

## Keeping in step with the web flow

`Flow/FlowRules.swift` ports `frontend/src/lib/flow.ts`, and
`Flow/FlowRouting.swift` ports the routing in `Entry.tsx`, `Consent.tsx`,
`Checklist.tsx` and `Status.tsx`. A routing change on either side needs the
other. `ConsentVersion.current` must match `CONSENT_VERSION` in
`frontend/src/lib/consentApi.ts`.
