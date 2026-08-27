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
import Foundation
import PackageModel
import struct TSCUtility.Version

/// Serializes a resolved list of `WorkspaceOverridesJSONParser.Override`
/// entries back to the on-disk `.swiftpm/configuration/workspace-overrides.json`
/// format understood by `WorkspaceOverridesJSONParser.parse(v1:...)`.
///
/// Companion to `WorkspaceOverridesJSONParser`. Used by the
/// `swift workspace override` CLI subcommand family (`add`, `remove`)
/// to update the file without hand-editing JSON. Round-trips through
/// `parse` are lossless.
///
/// Determinism: entries are alphabetized by identity in the output so
/// repeated `add`/`remove` operations that end in the same logical
/// override set produce byte-identical output, avoiding spurious git
/// diffs.
public enum WorkspaceOverridesJSONWriter {
    /// Serializes overrides to the v1 wire format.
    /// - Parameter overrides: The overrides to write, in any order.
    /// - Returns: A pretty-printed JSON string, ready to write to disk.
    public static func writeV1(
        overrides: [WorkspaceOverridesJSONParser.Override],
    ) throws -> String {
        let wire = overrides
            .sorted { $0.identity.description < $1.identity.description }
            .map(Self.toWire)
        let doc = OutputDocument(version: 1, overrides: wire)
        let encoder = JSONEncoder.makeWithDefaults()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Wire format

    private struct OutputDocument: Encodable {
        let version: Int
        let overrides: [WireOverride]
    }

    private struct WireOverride: Encodable {
        let identity: String
        let kind: Serialization.PackageDependency.Kind
    }

    // MARK: - Conversion

    private static func toWire(
        _ override: WorkspaceOverridesJSONParser.Override,
    ) -> WireOverride {
        let kind: Serialization.PackageDependency.Kind
        switch override.overridingDependency {
        case .fileSystem(let fs):
            kind = .fileSystem(
                name: fs.nameForTargetDependencyResolutionOnly,
                path: fs.path.pathString,
            )
        case .sourceControl(let sc):
            let location: String
            switch sc.location {
            case .local(let abs):
                location = abs.pathString
            case .remote(let url):
                location = url.absoluteString
            }
            kind = .sourceControl(
                name: sc.nameForTargetDependencyResolutionOnly,
                location: location,
                requirement: .init(sc.requirement),
            )
        case .registry(let reg):
            kind = .registry(
                id: reg.identity.description,
                requirement: .init(reg.requirement),
            )
        case .workspaceMember, .workspaceInherited:
            preconditionFailure(
                "workspace-scoped deps (.workspaceMember / .workspaceInherited) cannot appear in workspace overrides; the parser rejects them, so this branch is unreachable in practice."
            )
        }
        return WireOverride(
            identity: override.identity.description,
            kind: kind,
        )
    }
}

extension Serialization.PackageDependency.SourceControlRequirement {
    fileprivate init(_ requirement: PackageDependency.SourceControl.Requirement) {
        switch requirement {
        case .exact(let version):
            self = .exact(.init(version))
        case .range(let range):
            self = .range(lowerBound: .init(range.lowerBound), upperBound: .init(range.upperBound))
        case .revision(let revision):
            self = .revision(revision)
        case .branch(let branch):
            self = .branch(branch)
        }
    }
}

extension Serialization.PackageDependency.RegistryRequirement {
    fileprivate init(_ requirement: PackageDependency.Registry.Requirement) {
        switch requirement {
        case .exact(let version):
            self = .exact(.init(version))
        case .range(let range):
            self = .range(lowerBound: .init(range.lowerBound), upperBound: .init(range.upperBound))
        }
    }
}

extension Serialization.Version {
    fileprivate init(_ version: TSCUtility.Version) {
        self.init(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            prereleaseIdentifiers: version.prereleaseIdentifiers,
            buildMetadataIdentifiers: version.buildMetadataIdentifiers,
        )
    }
}
