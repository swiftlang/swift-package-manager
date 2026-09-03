//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import PackageModel
import Testing
import struct TSCUtility.Version

struct EnabledTraitVersionIdentityTests {
    @Test
    func isolatesEqualPrecedenceVersionIdentifiers() {
        var traits = EnabledTraitsMap.VersionedTraits()
        let plain = Version("1.2.3")
        let debug = Version("1.2.3+debug")
        let release = Version("1.2.3+release")

        traits.set(plain, enabledTraits: ["Plain"])
        traits.set(debug, enabledTraits: ["Debug"])
        traits.set(release, enabledTraits: ["Release"])

        #expect(traits.at(plain) == ["Plain"])
        #expect(traits.at(debug) == ["Debug"])
        #expect(traits.at(release) == ["Release"])
    }
}
