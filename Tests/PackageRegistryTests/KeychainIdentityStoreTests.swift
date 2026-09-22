//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageRegistry
import Testing

private let mona = KeychainIdentityAttributes(
    commonName: "Mona Lisa",
    hash: "737879F39CE872C961652C7EBCDE94B712C3E20A"
)
private let monaDuplicate = KeychainIdentityAttributes(
    commonName: "Mona Lisa",
    hash: "3D5B0764BA7DE45B0CD7DEB429FFBF70F5A07C1E"
)
private let anonymous = KeychainIdentityAttributes(
    commonName: nil,
    hash: "0123456789ABCDEF0123456789ABCDEF01234567"
)

@Suite("Keychain Identity Selection") struct KeychainIdentitySelectionTests {
    @Test func matchesCommonNameExactly() {
        let selection = KeychainIdentityMatch.select(
            from: [anonymous, mona],
            matching: .commonName("Mona Lisa")
        )

        #expect(selection == .match(index: 1))
    }

    @Test func commonNameMatchIsCaseSensitive() {
        let selection = KeychainIdentityMatch.select(
            from: [mona],
            matching: .commonName("mona lisa")
        )

        #expect(selection == .notFound)
    }

    @Test func reportsNoMatchForUnknownCommonName() {
        let selection = KeychainIdentityMatch.select(
            from: [mona, anonymous],
            matching: .commonName("Someone Else")
        )

        #expect(selection == .notFound)
    }

    @Test func reportsAmbiguousCommonNameInInputOrder() {
        let selection = KeychainIdentityMatch.select(
            from: [mona, anonymous, monaDuplicate],
            matching: .commonName("Mona Lisa")
        )

        #expect(selection == .ambiguous([mona, monaDuplicate]))
    }

    @Test func matchesHashExactly() {
        let selection = KeychainIdentityMatch.select(
            from: [anonymous, mona],
            matching: .hash(mona.hash)
        )

        #expect(selection == .match(index: 1))
    }

    @Test func matchesHashCaseInsensitively() {
        let selection = KeychainIdentityMatch.select(
            from: [mona],
            matching: .hash(mona.hash.lowercased())
        )

        #expect(selection == .match(index: 0))
    }

    @Test func matchesHashWithColons() {
        let selection = KeychainIdentityMatch.select(
            from: [mona],
            matching: .hash("73:78:79:F3:9C:E8:72:C9:61:65:2C:7E:BC:DE:94:B7:12:C3:E2:0A")
        )

        #expect(selection == .match(index: 0))
    }

    @Test func reportsNoMatchForUnknownHash() {
        let selection = KeychainIdentityMatch.select(
            from: [mona, anonymous],
            matching: .hash("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")
        )

        #expect(selection == .notFound)
    }

    @Test func reportsNoMatchForEmptyKeychain() {
        let selection = KeychainIdentityMatch.select(from: [], matching: .commonName("Mona Lisa"))

        #expect(selection == .notFound)
    }

    @Test func hashesCertificateBytesAsUppercaseSHA1() {
        let hash = KeychainIdentityAttributes.certificateHash(Array("abc".utf8))

        #expect(hash == "A9993E364706816ABA3E25717850C26C9CD0D89D")
    }
}
