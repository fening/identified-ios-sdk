# Releasing to CocoaPods trunk

Pods: `Identified` and `IdentifiedCore` (the SDK is two Swift modules; the first depends on the
second). Both podspecs carry the same version, which must equal the git tag. Trunk releases
cannot be edited; a bad build means a new version.

## One-time setup (owner)

1. `pod trunk register <your email> 'Your Name'`, then click the link CocoaPods emails you.
2. `pod trunk me` should list the session.

## Each release

1. Bump `s.version` in both podspecs, update the README, merge to `main`, then tag the merge
   commit with the same version and push it: `git tag 0.1.1 && git push origin 0.1.1`.
2. Lint: `pod lib lint Identified.podspec --include-podspecs=IdentifiedCore.podspec --allow-warnings`
   (also with `--use-libraries`). The warnings are two deprecated camera APIs in
   `CameraController.swift`; fix them in a hardware-tested change, not in a release commit.
3. Push the dependency first, then the SDK (trunk resolves dependencies at push time):
   `pod trunk push IdentifiedCore.podspec --allow-warnings`
   `pod trunk push Identified.podspec --allow-warnings`
4. Verify from a clean Podfile: `pod 'Identified', '0.1.1'` with `pod install --repo-update`, then
   build. Check <https://cocoapods.org/pods/Identified> (search can lag by an hour).
5. Confirm SwiftPM still resolves the tag: `swift package resolve` in a scratch package.
