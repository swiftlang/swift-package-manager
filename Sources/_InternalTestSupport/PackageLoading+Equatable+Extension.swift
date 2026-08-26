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

import PackageLoading

/// Test-only `Equatable` conformance for
/// `WorkspaceManifestJSONParser.Member`.
///
/// Production code intentionally does not conform this type to
/// `Equatable` — the parser output is consumed by
/// `PackageWorkspace`, which never compares members structurally.
/// Tests that assert "the parser produced this exact member" want a
/// single equality check rather than a field-by-field expansion; this
/// conformance provides that without leaking `Equatable` into the
/// production surface.
extension WorkspaceManifestJSONParser.Member: Equatable {
    public static func == (
        lhs: WorkspaceManifestJSONParser.Member,
        rhs: WorkspaceManifestJSONParser.Member,
    ) -> Bool {
        lhs.identity == rhs.identity
            && lhs.path == rhs.path
            && lhs.ignoredStateDirectories == rhs.ignoredStateDirectories
    }
}
