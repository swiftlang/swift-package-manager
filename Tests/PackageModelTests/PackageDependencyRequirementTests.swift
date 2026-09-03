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

import PackageModel
import Testing
import struct TSCUtility.Version

struct PackageDependencyRequirementTests {
    @Test
    func sourceControlExactRequirementsUseFullIdentifiers() {
        let plain = PackageDependency.SourceControl.Requirement.exact(Version("1.2.3"))
        let debug = PackageDependency.SourceControl.Requirement.exact(Version("1.2.3+debug"))
        let release = PackageDependency.SourceControl.Requirement.exact(Version("1.2.3+release"))

        #expect(plain != debug)
        #expect(debug != release)
        #expect(Set([plain, debug, release]).count == 3)

        let debugRange = PackageDependency.SourceControl.Requirement.range(
            Version("1.2.3+debug") ..< Version("2.0.0")
        )
        let releaseRange = PackageDependency.SourceControl.Requirement.range(
            Version("1.2.3+release") ..< Version("2.0.0")
        )
        #expect(debugRange == releaseRange)
        #expect(Set([debugRange, releaseRange]).count == 1)
    }

    @Test
    func registryExactRequirementsUseFullIdentifiers() {
        let plain = PackageDependency.Registry.Requirement.exact(Version("1.2.3"))
        let debug = PackageDependency.Registry.Requirement.exact(Version("1.2.3+debug"))
        let release = PackageDependency.Registry.Requirement.exact(Version("1.2.3+release"))

        #expect(plain != debug)
        #expect(debug != release)
        #expect(Set([plain, debug, release]).count == 3)

        let debugRange = PackageDependency.Registry.Requirement.range(
            Version("1.2.3+debug") ..< Version("2.0.0")
        )
        let releaseRange = PackageDependency.Registry.Requirement.range(
            Version("1.2.3+release") ..< Version("2.0.0")
        )
        #expect(debugRange == releaseRange)
        #expect(Set([debugRange, releaseRange]).count == 1)
    }
}
