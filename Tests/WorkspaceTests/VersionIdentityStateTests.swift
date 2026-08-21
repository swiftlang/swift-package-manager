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
import Testing
@testable import Workspace
import struct TSCUtility.Version

struct VersionIdentityStateTests {
    @Test
    func managedDependencyStatesUseFullIdentifiers() {
        let plain = Version("1.0.0")
        let debug = Version("1.0.0+debug")
        let release = Version("1.0.0+release")

        #expect(
            Workspace.ManagedDependency.State.registryDownload(version: plain, scmUrl: nil) !=
                .registryDownload(version: debug, scmUrl: nil)
        )
        #expect(
            Workspace.ManagedDependency.State.registryDownload(version: debug, scmUrl: nil) !=
                .registryDownload(version: release, scmUrl: nil)
        )
        #expect(
            Workspace.ManagedDependency.State.custom(version: debug, path: "/package") !=
                .custom(version: release, path: "/package")
        )
    }

    @Test
    func packageStateChangesUseFullIdentifiers() {
        let plain = Workspace.PackageStateChange.Requirement.version(Version("1.0.0"))
        let debug = Workspace.PackageStateChange.Requirement.version(Version("1.0.0+debug"))
        let release = Workspace.PackageStateChange.Requirement.version(Version("1.0.0+release"))

        #expect(plain != debug)
        #expect(debug != release)
    }
}
