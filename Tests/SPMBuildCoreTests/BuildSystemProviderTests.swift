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

import Basics
import SPMBuildCore
import Testing

struct BuildSystemProviderTests {
    @Test(
        arguments: [
            (BuildSystemProvider.Kind.native, "x86_64-unknown-linux-gnu", ".resources"),
            (.native, "arm64-apple-macosx", ".bundle"),
            (.swiftbuild, "x86_64-unknown-linux-gnu", ".bundle"),
            (.swiftbuild, "x86_64-unknown-windows-msvc", ".bundle"),
            (.swiftbuild, "arm64-apple-macosx", ".bundle"),
            (.xcode, "arm64-apple-macosx", ".bundle"),
        ]
    )
    func resourceBundleExtension(kind: BuildSystemProvider.Kind, triple: String, expected: String) throws {
        #expect(try kind.resourceBundleExtension(for: Triple(triple)) == expected)
    }
}
