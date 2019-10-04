// swift-tools-version:5.1

import PackageDescription
import Foundation

/// This string demonstrates as many complications of Unicode as possible.
let complicatedString = "πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄"
// π U+03C0: A simple BMP scalar.
//‎ שּׁ U+FB2C: Changes under both NFC and NFD.
// µ U+00B5: Changes under NFKC and NFKD.
// 𝄞 U+1D11E: Simple non‐BMP scalar.
// 🇺🇳 U+1F1FA U+1F1F3: Multi‐scalar character.
// 🇮🇱 U+1F1EE U+1F1F1: Second consecutive regional indicator. (Complicated grapheme breaking.)
// x̱̱̱̱̱̄̄̄̄̄ U+0078 (U+0331 U+0304) × 5: Extremely long combining sequence. (Also reordrant under normalization.)

// The following verifies that sources haven’t been normalized, which would reduce the test’s effectiveness.
var verify = "\u{03C0}\u{0FB2C}\u{00B5}\u{1D11E}\u{1F1FA}\u{1F1F3}\u{1F1EE}\u{1F1F1}\u{0078}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}"
assert(
    complicatedString.unicodeScalars.elementsEqual(verify.unicodeScalars),
    "\(complicatedString) ≠ \(verify)")

let package = Package(
    name: complicatedString,
    products: [
        .library(
            name: complicatedString,
            targets: [complicatedString]),
        .executable(name: complicatedString + "‐tool", targets: [complicatedString + "‐tool"])
    ],
    dependencies: [
        .package(url: "../UnicodeDependency‐\(complicatedString)", from: "1.0.0")
    ],
    targets: [
        .target(
            name: complicatedString,
            dependencies: [.product(name: "UnicodeDependency‐\(complicatedString)")]),
        .target(
            name: "C" + complicatedString),
        .target(
            name: complicatedString + "‐tool",
            dependencies: [.target(name: complicatedString)]),
        .testTarget(
            name: complicatedString + "Tests",
            dependencies: [
                .target(name: complicatedString),
                .target(name: "C" + complicatedString)
            ]),
    ]
)

// This section is separate on purpose.
// If the directory turns out to be illegal on a platform (Windows?),
// it can easily be removed with “#if !os(...)” and the rest of the test will still work.
let equivalentToASCII = "\u{037E}" // ερωτηματικό (greek question mark)
let ascii = "\u{3B}" // semicolon
// What follows is a nasty hack that requires sandboxing to be disabled. (--disable-sandbox)
// The target it creates can exist in this form on Linux and other platforms,
// but as soon as it is checked out on macOS, the macOS filesystem obliterates the distinction,
// leaving the test meaningless.
// Since much development of the SwiftPM repository occurs on macOS,
// maintaining the integrity of the test fixture requires regenerating this part of it each time.
import Foundation
let manifestURL = URL(fileURLWithPath: #file)
let packageRoot = manifestURL.deletingLastPathComponent()
let targetURL = packageRoot
    .appendingPathComponent("Sources")
    .appendingPathComponent(equivalentToASCII)
let sourceURL = targetURL.appendingPathComponent("Source.swift")
try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
try Data().write(to: targetURL.appendingPathComponent("\(equivalentToASCII).swift"))
package.targets.append(.target(name: ascii))
let tests = package.targets.first(where: { $0.type == .test })!
tests.dependencies.append(.target(name: ascii))
