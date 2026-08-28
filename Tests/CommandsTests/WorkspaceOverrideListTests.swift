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
import Foundation
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
struct WorkspaceOverrideListTests {
    private typealias List = SwiftWorkspaceCommand.Override.List

    private static let workspaceRoot = AbsolutePath("/repo")

    // MARK: - text format

    /// An empty overrides list renders as the `(no overrides
    /// declared)` hint in text format — same string the CLI printed
    /// before the multi-line refactor, so tooling that greps for that
    /// substring keeps working.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_emptyText_returnsEmptyHint() throws {
        let rendered = try List.renderList([], format: .text)

        #expect(rendered == "(no overrides declared)")
    }

    /// A `.fileSystem` override renders as a three-line block: the
    /// identity, the kind (`path`), and the resolved absolute
    /// location. No `requirement:` line because file-system overrides
    /// have no version constraint.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_pathText_showsKindAndLocation() throws {
        let override = WorkspaceOverridesJSONParser.Override(
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

        let rendered = try List.renderList([override], format: .text)

        #expect(rendered.contains("some-lib"))
        #expect(rendered.contains("kind: path"))
        #expect(rendered.contains("location: /repo/external/local-some-lib"))
        #expect(rendered.contains("requirement:") == false)
    }

    /// A `.sourceControl` override with an `.exact` requirement
    /// renders the identity, kind (`url`), location (the URL), and
    /// requirement (`exact 1.0.0`).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_urlWithExactText_showsRequirement() throws {
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .sourceControl(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                location: .remote(SourceControlURL("https://github.com/apple/foo.git")),
                requirement: .exact(Version(1, 0, 0)),
                productFilter: .everything,
                traits: nil,
                registryIdentity: nil,
            ),
        )

        let rendered = try List.renderList([override], format: .text)

        #expect(rendered.contains("kind: url"))
        #expect(rendered.contains("location: https://github.com/apple/foo.git"))
        #expect(rendered.contains("requirement: exact 1.0.0"))
    }

    /// A `.registry` override with a `.range` requirement renders the
    /// identity, kind (`registry`), location (the registry identity),
    /// and requirement (`range 1.0.0..<2.0.0`).
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_registryWithRangeText_showsRange() throws {
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .registry(
                identity: .plain("some-lib"),
                requirement: .range(Version(1, 0, 0)..<Version(2, 0, 0)),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let rendered = try List.renderList([override], format: .text)

        #expect(rendered.contains("kind: registry"))
        #expect(rendered.contains("location: some-lib"))
        #expect(rendered.contains("requirement: range 1.0.0..<2.0.0"))
    }

    /// Two overrides render as two blocks separated by a blank line —
    /// consumers grepping the output can rely on the blank-line
    /// delimiter to segment entries.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_multipleText_separatedByBlankLine() throws {
        let overrides = [
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("a-lib"),
                overridingDependency: .fileSystem(
                    identity: .plain("a-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: Self.workspaceRoot.appending("a"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("b-lib"),
                overridingDependency: .fileSystem(
                    identity: .plain("b-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: Self.workspaceRoot.appending("b"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
        ]

        let rendered = try List.renderList(overrides, format: .text)

        #expect(rendered.contains("a-lib\n  kind: path\n  location: /repo/a"))
        #expect(rendered.contains("b-lib\n  kind: path\n  location: /repo/b"))
        #expect(rendered.contains("/repo/a\n\nb-lib"))
    }

    // MARK: - JSON format

    /// An empty overrides list renders as an empty JSON array (`[]`)
    /// so downstream tooling gets a valid parseable document
    /// regardless of whether any overrides exist.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_emptyJson_returnsEmptyArray() throws {
        let rendered = try List.renderList([], format: .json)

        let data = try #require(rendered.data(using: .utf8))
        let array = try JSONDecoder().decode([ListEntryJSON].self, from: data)
        #expect(array.isEmpty)
    }

    /// A mixed list of all three kinds renders as a JSON array of
    /// per-override objects. Each object carries `identity`, `kind`,
    /// `location`, and (for url/registry) `requirement`.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func renderList_multipleKindsJson_isValidArrayWithExpectedFields() throws {
        let overrides = [
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("path-lib"),
                overridingDependency: .fileSystem(
                    identity: .plain("path-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: Self.workspaceRoot.appending("p"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("url-lib"),
                overridingDependency: .sourceControl(
                    identity: .plain("url-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    location: .remote(SourceControlURL("https://github.com/apple/foo.git")),
                    requirement: .exact(Version(1, 0, 0)),
                    productFilter: .everything,
                    traits: nil,
                    registryIdentity: nil,
                ),
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("reg-lib"),
                overridingDependency: .registry(
                    identity: .plain("reg-lib"),
                    requirement: .range(Version(1, 0, 0)..<Version(2, 0, 0)),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
        ]

        let rendered = try List.renderList(overrides, format: .json)
        let data = try #require(rendered.data(using: .utf8))
        let array = try JSONDecoder().decode([ListEntryJSON].self, from: data)
        try #require(array.count == 3)

        let pathEntry = try #require(array.first { $0.identity == "path-lib" })
        #expect(pathEntry.kind == "path")
        #expect(pathEntry.location == "/repo/p")
        #expect(pathEntry.requirement == nil)

        let urlEntry = try #require(array.first { $0.identity == "url-lib" })
        #expect(urlEntry.kind == "url")
        #expect(urlEntry.location == "https://github.com/apple/foo.git")
        #expect(urlEntry.requirement == .exact("1.0.0"))

        let regEntry = try #require(array.first { $0.identity == "reg-lib" })
        #expect(regEntry.kind == "registry")
        #expect(regEntry.location == "reg-lib")
        #expect(regEntry.requirement == .range(lowerBound: "1.0.0", upperBound: "2.0.0"))
    }
}
