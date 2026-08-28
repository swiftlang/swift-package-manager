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
@_spi(SwiftPMInternal) @testable import Commands
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct CleanDiagnosticsTests {
    /// `cleaningWorkspaceBuildDirectory` is an `info`-severity
    /// diagnostic that announces the workspace-scoped `.build/`
    /// location before Clean removes it. Locking severity + message
    /// shape so the CLI stays consistent across cleaning invocations.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func cleaningWorkspaceBuildDirectory_isInfoWithPath() throws {
        let path = AbsolutePath("/repo/.build")
        let diagnostic = Basics.Diagnostic.cleaningWorkspaceBuildDirectory(path: path)

        #expect(diagnostic.severity == .info)
        #expect(diagnostic.message.contains("cleaning workspace build directory"))
        #expect(diagnostic.message.contains("/repo/.build"))
    }

    /// `packageSelectorHasNoEffectForClean` is an `info`-severity
    /// diagnostic emitted when a user passes `--package X` to
    /// `swift package clean` under a workspace. The workspace uses a
    /// shared `.build/` so per-package restriction is meaningless —
    /// the command still succeeds. Info (not warning/error) because
    /// the request is benign; the user just gets told the flag was
    /// ignored.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func packageSelectorHasNoEffectForClean_isInfoWithHint() throws {
        let diagnostic = Basics.Diagnostic.packageSelectorHasNoEffectForClean()

        #expect(diagnostic.severity == .info)
        #expect(diagnostic.message.contains("--package"))
        #expect(diagnostic.message.contains("clean"))
        #expect(diagnostic.message.contains("shared build directory"))
    }
}
