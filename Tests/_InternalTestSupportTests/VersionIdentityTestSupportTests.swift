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

import Testing
import _InternalTestSupport
import struct TSCUtility.Version

struct VersionIdentityTestSupportTests {
    @Test
    func manifestLoaderKeysUseFullIdentifiers() {
        let plain = MockManifestLoader.Key(url: "/package", version: Version("1.0.0"))
        let debug = MockManifestLoader.Key(url: "/package", version: Version("1.0.0+debug"))
        let release = MockManifestLoader.Key(url: "/package", version: Version("1.0.0+release"))

        #expect(plain != debug)
        #expect(debug != release)
        #expect(Set([plain, debug, release]).count == 3)
    }
}
