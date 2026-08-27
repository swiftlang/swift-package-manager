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
import PackageLoading
import PackageModel
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceOverridesJSONWriterTests {
    /// An empty overrides array serializes to a v1 document with an
    /// empty `overrides` list. Callers depend on this shape being
    /// stable so that `parse(v1:...)` on the written output is a
    /// no-op.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func writeV1_withEmptyOverrides_producesEmptyArray() throws {
        let json = try WorkspaceOverridesJSONWriter.writeV1(overrides: [])

        let reparsed = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: AbsolutePath("/repo"),
        )
        #expect(reparsed.isEmpty)
    }

    /// A single fileSystem override serializes and round-trips
    /// through the parser without loss. This is the primary write →
    /// read cycle the `add` CLI subcommand relies on.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func writeV1_withOneFileSystemOverride_roundTripsThroughParser() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let override = WorkspaceOverridesJSONParser.Override(
            identity: .plain("some-lib"),
            overridingDependency: .fileSystem(
                identity: .plain("some-lib"),
                nameForTargetDependencyResolutionOnly: nil,
                path: workspaceRoot.appending(components: "external", "local-some-lib"),
                productFilter: .everything,
                traits: nil,
            ),
        )

        let json = try WorkspaceOverridesJSONWriter.writeV1(overrides: [override])
        let reparsed = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        try #require(reparsed.count == 1)
        #expect(reparsed[0] == override)
    }

    /// Overrides are written alphabetized by identity so
    /// re-serializing the same set of overrides produces
    /// byte-identical output regardless of user-supplied insertion
    /// order. Deterministic on-disk representation avoids spurious
    /// git diffs when the CLI mutates the file.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func writeV1_withMultipleOverrides_sortsByIdentity() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let makeFS: (String) -> WorkspaceOverridesJSONParser.Override = { identity in
            .init(
                identity: .plain(identity),
                overridingDependency: .fileSystem(
                    identity: .plain(identity),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(identity),
                    productFilter: .everything,
                    traits: nil,
                ),
            )
        }
        let unsorted: [WorkspaceOverridesJSONParser.Override] = [
            makeFS("gamma"),
            makeFS("alpha"),
            makeFS("beta"),
        ]

        let json = try WorkspaceOverridesJSONWriter.writeV1(overrides: unsorted)
        let reparsed = try WorkspaceOverridesJSONParser.parse(
            v1: json,
            workspaceRoot: workspaceRoot,
        )

        #expect(reparsed.map { $0.identity.description } == ["alpha", "beta", "gamma"])
    }

    /// Two writes with the identical input produce byte-identical
    /// output. This is the strong-form determinism guarantee: the
    /// writer has no hidden state (timestamps, iteration order over
    /// a `Set`, random UUIDs, etc.) leaking into the JSON.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func writeV1_withSameInput_producesByteIdenticalOutput() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let overrides = [
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("some-lib"),
                overridingDependency: .fileSystem(
                    identity: .plain("some-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(components: "external", "some-lib"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
            WorkspaceOverridesJSONParser.Override(
                identity: .plain("other-lib"),
                overridingDependency: .fileSystem(
                    identity: .plain("other-lib"),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(components: "external", "other-lib"),
                    productFilter: .everything,
                    traits: nil,
                ),
            ),
        ]

        let first = try WorkspaceOverridesJSONWriter.writeV1(overrides: overrides)
        let second = try WorkspaceOverridesJSONWriter.writeV1(overrides: overrides)

        #expect(first == second)
    }

    /// Two writes with the same *set* of overrides but supplied in
    /// different orders produce byte-identical output. Guarantees
    /// the `swift workspace override add` CLI can freely append to
    /// the internal list — the on-disk file is normalized regardless
    /// of insertion order — so mutations produce clean, minimal git
    /// diffs.
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func writeV1_withSameSetInDifferentOrder_producesByteIdenticalOutput() throws {
        let workspaceRoot = AbsolutePath("/repo")
        let makeFS: (String) -> WorkspaceOverridesJSONParser.Override = { identity in
            .init(
                identity: .plain(identity),
                overridingDependency: .fileSystem(
                    identity: .plain(identity),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: workspaceRoot.appending(identity),
                    productFilter: .everything,
                    traits: nil,
                ),
            )
        }
        let orderA: [WorkspaceOverridesJSONParser.Override] = [
            makeFS("alpha"),
            makeFS("beta"),
            makeFS("gamma"),
        ]
        let orderB: [WorkspaceOverridesJSONParser.Override] = [
            makeFS("gamma"),
            makeFS("alpha"),
            makeFS("beta"),
        ]

        let jsonA = try WorkspaceOverridesJSONWriter.writeV1(overrides: orderA)
        let jsonB = try WorkspaceOverridesJSONWriter.writeV1(overrides: orderB)

        #expect(jsonA == jsonB)
    }
}
