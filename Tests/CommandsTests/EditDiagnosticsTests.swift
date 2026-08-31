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
struct EditDiagnosticsTests {
    /// `editUnsupportedUnderWorkspace` is an `error`-severity
    /// diagnostic emitted when `swift package edit` (or `unedit`)
    /// runs under a SwiftPM workspace. The message MUST steer the
    /// user toward the workspace-scoped alternative
    /// `swift package workspace override`, not the generic
    /// "will be addressed in a follow-up" placeholder — override
    /// already covers the redirect-a-dep-to-a-local-checkout use
    /// case that `edit` served in single-package mode.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func editUnsupportedUnderWorkspace_isErrorPointingAtWorkspaceOverride() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let diagnostic = Basics.Diagnostic.editUnsupportedUnderWorkspace(
            workspaceRoot: workspaceRoot,
        )

        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains("swift package edit"))
        #expect(diagnostic.message.contains("workspace"))
        // Actionable redirect: never surface the "will be addressed
        // in a follow-up" placeholder. Users need a concrete next
        // step, and `override` is it.
        #expect(diagnostic.message.contains("swift package workspace override"))
        #expect(diagnostic.message.contains("follow-up") == false)
        // Naming the workspace root helps the user see WHICH
        // workspace triggered the rejection when they're deep in a
        // member subdirectory.
        #expect(diagnostic.message.contains("/repo"))
    }

    /// Parity coverage for `unedit`: the same rejection message
    /// shape applies to `swift package unedit`. Same reasoning —
    /// `unedit` is the inverse of `edit`, and neither has a well-
    /// defined meaning under a workspace's shared checkout state.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func uneditUnsupportedUnderWorkspace_isErrorPointingAtWorkspaceOverride() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let diagnostic = Basics.Diagnostic.uneditUnsupportedUnderWorkspace(
            workspaceRoot: workspaceRoot,
        )

        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains("swift package unedit"))
        #expect(diagnostic.message.contains("workspace"))
        #expect(diagnostic.message.contains("swift package workspace override"))
        #expect(diagnostic.message.contains("follow-up") == false)
        #expect(diagnostic.message.contains("/repo"))
    }
}
