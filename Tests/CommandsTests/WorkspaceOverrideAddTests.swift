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
@testable import Commands
import PackageLoading
import PackageModel
import Testing
import _InternalTestSupport
import struct TSCUtility.Version

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOverrideAddTests {
    private static let workspaceRoot = AbsolutePath("/repo")

    // MARK: - `override add path`

    /// A relative path resolves against the workspace root and
    /// produces a `.fileSystem` override.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func path_withRelativePath_resolvesAgainstWorkspaceRoot() throws {
        let override = try SwiftWorkspaceCommand.Override.Add.Path.buildOverride(
            identity: "some-lib",
            workspaceRoot: Self.workspaceRoot,
            path: "external/local-some-lib",
        )

        let expected = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: Self.workspaceRoot.appending(
                    try RelativePath(validating: "external/local-some-lib"),
                ),
                productFilter: .everything,
                traits: nil,
            ),
        )
        #expect(override == expected)
    }

    // MARK: - `override add url`

    /// `override add url ... --exact 1.0.0` produces a `.sourceControl`
    /// override with an `.exact` requirement.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func url_withExact_producesSourceControlExact() throws {
        let override = try SwiftWorkspaceCommand.Override.Add.Url.buildOverride(
            identity: "some-lib",
            url: "https://github.com/apple/example-some-lib.git",
            exact: Version(1, 0, 0),
            branch: nil,
            revision: nil,
            from: nil,
            upToNextMinorFrom: nil,
            to: nil,
        )

        switch override.overridingDependency {
        case .sourceControl(let sc):
            #expect(sc.location == .remote(SourceControlURL("https://github.com/apple/example-some-lib.git")))
            #expect(sc.requirement == .exact(Version(1, 0, 0)))
        default:
            Issue.record("expected .sourceControl override; got \(override.overridingDependency)")
        }
    }

    /// `override add url ... --from 1.0.0 --to 2.0.0` produces a
    /// `.sourceControl` override with a bounded `.range` requirement.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func url_withFromToRange_producesSourceControlRange() throws {
        let override = try SwiftWorkspaceCommand.Override.Add.Url.buildOverride(
            identity: "some-lib",
            url: "https://github.com/apple/example-some-lib.git",
            exact: nil,
            branch: nil,
            revision: nil,
            from: Version(1, 0, 0),
            upToNextMinorFrom: nil,
            to: Version(2, 0, 0),
        )

        switch override.overridingDependency {
        case .sourceControl(let sc):
            #expect(sc.requirement == .range(Version(1, 0, 0)..<Version(2, 0, 0)))
        default:
            Issue.record("expected .sourceControl override; got \(override.overridingDependency)")
        }
    }

    /// `override add url` with no version qualifier is a hard error —
    /// source-control deps require a version constraint.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func url_withNoRequirement_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.sourceControlRequiresVersionQualifier) {
            try SwiftWorkspaceCommand.Override.Add.Url.buildOverride(
                identity: "some-lib",
                url: "https://github.com/apple/foo.git",
                exact: nil,
                branch: nil,
                revision: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil,
            )
        }
    }

    /// Multiple version qualifiers on `override add url` is a hard
    /// error — the requirement must be unambiguous.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func url_withExactAndBranch_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.multipleVersionQualifiers) {
            try SwiftWorkspaceCommand.Override.Add.Url.buildOverride(
                identity: "some-lib",
                url: "https://github.com/apple/foo.git",
                exact: Version(1, 0, 0),
                branch: "main",
                revision: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil,
            )
        }
    }

    /// `override add url ... --exact 1.0.0 --to 2.0.0` is a hard
    /// error — `--to` needs a range start (`--from` or
    /// `--up-to-next-minor-from`), and `--exact` isn't one.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func url_withExactAndTo_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.toRequiresRangeStart) {
            try SwiftWorkspaceCommand.Override.Add.Url.buildOverride(
                identity: "some-lib",
                url: "https://github.com/apple/foo.git",
                exact: Version(1, 0, 0),
                branch: nil,
                revision: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: Version(2, 0, 0),
            )
        }
    }

    // MARK: - `override add registry`

    /// `override add registry <identity> --exact 1.2.3` produces a
    /// `.registry` override. The override's identity plays a dual
    /// role — it names both the declared dep to redirect AND the
    /// registry identity to resolve against.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func registry_withExact_producesRegistryExact() throws {
        let override = try SwiftWorkspaceCommand.Override.Add.Registry.buildOverride(
            identity: "apple.example-some-lib",
            exact: Version(1, 2, 3),
            from: nil,
            upToNextMinorFrom: nil,
            to: nil,
        )

        switch override.overridingDependency {
        case .registry(let reg):
            #expect(reg.identity == .plain("apple.example-some-lib"))
            #expect(reg.requirement == .exact(Version(1, 2, 3)))
        default:
            Issue.record("expected .registry override; got \(override.overridingDependency)")
        }
    }

    /// `override add registry` with no version qualifier is a hard
    /// error — registry deps require a version constraint.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func registry_withNoRequirement_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.registryRequiresVersionQualifier) {
            try SwiftWorkspaceCommand.Override.Add.Registry.buildOverride(
                identity: "apple.some-lib",
                exact: nil,
                from: nil,
                upToNextMinorFrom: nil,
                to: nil,
            )
        }
    }

    /// `override add registry ... --exact 1.0.0 --from 2.0.0` is a
    /// hard error — the requirement must be unambiguous. Mirrors
    /// `url_withExactAndBranch_throws` on the registry side.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func registry_withExactAndFrom_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.multipleVersionQualifiers) {
            try SwiftWorkspaceCommand.Override.Add.Registry.buildOverride(
                identity: "apple.some-lib",
                exact: Version(1, 0, 0),
                from: Version(2, 0, 0),
                upToNextMinorFrom: nil,
                to: nil,
            )
        }
    }

    /// `override add registry ... --exact 1.0.0 --to 2.0.0` is a hard
    /// error — `--to` needs a range start (`--from` or
    /// `--up-to-next-minor-from`), and `--exact` isn't one. Mirrors
    /// `url_withExactAndTo_throws` on the registry side.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func registry_withExactAndTo_throws() throws {
        #expect(throws: WorkspaceOverrideAddError.toRequiresRangeStart) {
            try SwiftWorkspaceCommand.Override.Add.Registry.buildOverride(
                identity: "apple.some-lib",
                exact: Version(1, 0, 0),
                from: nil,
                upToNextMinorFrom: nil,
                to: Version(2, 0, 0),
            )
        }
    }
}
