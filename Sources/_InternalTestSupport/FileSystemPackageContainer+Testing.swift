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
import Workspace

extension FileSystemPackageContainer {
    /// Loads and returns the container's manifest. Intended for tests
    /// that need to inspect the manifest without going through
    /// `getUnversionedDependencies` (which triggers `packageRef` and,
    /// for a `.workspaceInherited` dep whose `resolved` field has not
    /// been populated by the workspace load, would `preconditionFailure`).
    public func loadedManifestForTesting() async throws -> Manifest {
        try await self.loadManifest()
    }
}
