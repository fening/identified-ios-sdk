import Foundation
import Testing
@testable import Identified

/// Every key the source asks for exists, and every string in the file is used:
/// a renamed key or a deleted screen shows up here, not as a raw key on a
/// subject's screen.
private let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/Identified")

private func keysInSource() throws -> Set<String> {
    let pattern = try NSRegularExpression(pattern: #"L10n\.(?:string|format)\("([a-z0-9_.]+)""#)
    var keys = Set<String>()
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
        }
    }
    return keys
}

private func keysInStrings() throws -> Set<String> {
    let url = sources.appendingPathComponent("Resources/en.lproj/Localizable.strings")
    let text = try String(contentsOf: url, encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: #"^"([a-z0-9_.]+)"\s*="#, options: .anchorsMatchLines)
    return Set(pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
        String(text[Range($0.range(at: 1), in: text)!])
    })
}

@Test func everyKeyInTheSourceHasAString() throws {
    let missing = try keysInSource().filter { L10n.string($0) == $0 }
    #expect(missing.isEmpty, "No string for: \(missing.sorted())")
}

@Test func everyStringIsUsed() throws {
    let unused = try keysInStrings().subtracting(keysInSource())
    #expect(unused.isEmpty, "Unused strings: \(unused.sorted())")
}

@Test func formatsArguments() {
    #expect(L10n.format("flow.step", 2, 5) == "Step 2 of 5")
}
