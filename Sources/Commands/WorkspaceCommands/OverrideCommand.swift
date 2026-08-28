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

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageLoading
import PackageModel
import Workspace

import struct TSCUtility.Version

extension SwiftWorkspaceCommand {
    /// Manage workspace-level dependency overrides
    /// (`.swiftpm/configuration/workspace-overrides.json`).
    struct Override: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "override",
            abstract: "Manage developer-local dependency overrides for the workspace.",
            subcommands: [Add.self, Remove.self, List.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )
    }
}

extension SwiftWorkspaceCommand.Override {
    /// Add or replace a workspace-level dependency override.
    struct Add: ParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or replace a workspace-level dependency override.",
            subcommands: [Path.self, Url.self, Registry.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )
    }
}

extension SwiftWorkspaceCommand.Override.Add {
    /// Redirect a workspace-level dependency to a local filesystem
    /// path. Relative paths resolve against the workspace root.
    struct Path: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Redirect a workspace-level dependency to a local filesystem path.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the workspace-level dependency to override.")
        var identity: String

        @Argument(help: "Local filesystem path (relative paths resolve against the workspace root).")
        var path: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let override = try Self.buildOverride(
                identity: self.identity,
                workspaceRoot: workspaceRoot,
                path: self.path,
            )
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            try WorkspaceOverridesManager.add(
                override: override,
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure builder: resolves `path` (relative to `workspaceRoot`
        /// when not already absolute) and returns a `.fileSystem`
        /// override for `identity`.
        static func buildOverride(
            identity: String,
            workspaceRoot: AbsolutePath,
            path: String,
        ) throws -> WorkspaceOverridesJSONParser.Override {
            let target: AbsolutePath
            if let absolute = try? AbsolutePath(validating: path) {
                target = absolute
            } else {
                target = workspaceRoot.appending(try RelativePath(validating: path))
            }
            return WorkspaceOverridesJSONParser.Override(
                identity: .plain(identity),
                overridingDependency: .fileSystem(
                    identity: .plain(identity),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: target,
                    productFilter: .everything,
                    traits: nil,
                ),
            )
        }
    }

    /// Redirect a workspace-level dependency to a source-control URL.
    /// Exactly one of the version qualifiers (`--exact`, `--branch`,
    /// `--revision`, `--from`, `--up-to-next-minor-from`) must be
    /// supplied. `--to` pairs with `--from` or `--up-to-next-minor-from`
    /// to bound the upper end of the range.
    struct Url: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "url",
            abstract: "Redirect a workspace-level dependency to a source-control URL.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the workspace-level dependency to override.")
        var identity: String

        @Argument(help: "The source-control URL of the redirect target.")
        var url: String

        @Option(help: "The exact package version to depend on.")
        var exact: Version?

        @Option(help: "The specific package revision to depend on.")
        var revision: String?

        @Option(help: "The branch of the package to depend on.")
        var branch: String?

        @Option(help: "The package version to depend on (up to the next major version).")
        var from: Version?

        @Option(help: "The package version to depend on (up to the next minor version).")
        var upToNextMinorFrom: Version?

        @Option(help: "Specify upper bound on the package version range (exclusive).")
        var to: Version?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let override = try Self.buildOverride(
                identity: self.identity,
                url: self.url,
                exact: self.exact,
                branch: self.branch,
                revision: self.revision,
                from: self.from,
                upToNextMinorFrom: self.upToNextMinorFrom,
                to: self.to,
            )
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            try WorkspaceOverridesManager.add(
                override: override,
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure builder: composes the source-control requirement from
        /// the given version qualifiers, then returns a `.sourceControl`
        /// override. Throws when zero or multiple qualifiers are set,
        /// or when `--to` is supplied without a valid range start.
        static func buildOverride(
            identity: String,
            url: String,
            exact: Version?,
            branch: String?,
            revision: String?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> WorkspaceOverridesJSONParser.Override {
            let requirement = try Self.sourceControlRequirement(
                exact: exact,
                branch: branch,
                revision: revision,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to,
            )
            return WorkspaceOverridesJSONParser.Override(
                identity: .plain(identity),
                overridingDependency: .sourceControl(
                    identity: .plain(identity),
                    nameForTargetDependencyResolutionOnly: nil,
                    location: .remote(SourceControlURL(url)),
                    requirement: requirement,
                    productFilter: .everything,
                    traits: nil,
                    registryIdentity: nil,
                ),
            )
        }

        private static func sourceControlRequirement(
            exact: Version?,
            branch: String?,
            revision: String?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> PackageDependency.SourceControl.Requirement {
            var candidates: [PackageDependency.SourceControl.Requirement] = []
            if let exact { candidates.append(.exact(exact)) }
            if let branch { candidates.append(.branch(branch)) }
            if let revision { candidates.append(.revision(revision)) }
            if let from { candidates.append(.range(from..<Version(from.major + 1, 0, 0))) }
            if let upToNextMinorFrom {
                candidates.append(
                    .range(
                        upToNextMinorFrom..<Version(upToNextMinorFrom.major, upToNextMinorFrom.minor + 1, 0),
                    ),
                )
            }
            guard let first = candidates.first else {
                throw WorkspaceOverrideAddError.sourceControlRequiresVersionQualifier
            }
            guard candidates.count == 1 else {
                throw WorkspaceOverrideAddError.multipleVersionQualifiers
            }
            if let to {
                guard case .range(let range) = first else {
                    throw WorkspaceOverrideAddError.toRequiresRangeStart
                }
                return .range(range.lowerBound..<to)
            }
            return first
        }
    }

    /// Redirect a workspace-level dependency to be resolved via the
    /// package registry. Exactly one of the version qualifiers
    /// (`--exact`, `--from`, `--up-to-next-minor-from`) must be
    /// supplied — branch and revision are rejected because the registry
    /// requirement enum doesn't support them. `--to` pairs with
    /// `--from` or `--up-to-next-minor-from` to bound the upper end of
    /// the range.
    ///
    /// The override's identity plays a dual role: it names the
    /// declared dependency to redirect AND the registry identity to
    /// resolve. The parser reconstructs the redirected dep using the
    /// override's identity as the registry key, so a distinct target
    /// identity would be silently discarded — the CLI is intentionally
    /// single-positional to match that constraint.
    struct Registry: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "registry",
            abstract: "Redirect a workspace-level dependency to be resolved via the package registry.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the workspace-level dependency to override; also serves as the registry identity to resolve against.")
        var identity: String

        @Option(help: "The exact package version to depend on.")
        var exact: Version?

        @Option(help: "The package version to depend on (up to the next major version).")
        var from: Version?

        @Option(help: "The package version to depend on (up to the next minor version).")
        var upToNextMinorFrom: Version?

        @Option(help: "Specify upper bound on the package version range (exclusive).")
        var to: Version?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let override = try Self.buildOverride(
                identity: self.identity,
                exact: self.exact,
                from: self.from,
                upToNextMinorFrom: self.upToNextMinorFrom,
                to: self.to,
            )
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            try WorkspaceOverridesManager.add(
                override: override,
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure builder: composes the registry requirement from the
        /// given version qualifiers, then returns a `.registry`
        /// override. Throws when zero or multiple qualifiers are set,
        /// or when `--to` is supplied without a valid range start.
        static func buildOverride(
            identity: String,
            exact: Version?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> WorkspaceOverridesJSONParser.Override {
            let requirement = try Self.registryRequirement(
                exact: exact,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to,
            )
            return WorkspaceOverridesJSONParser.Override(
                identity: .plain(identity),
                overridingDependency: .registry(
                    identity: .plain(identity),
                    requirement: requirement,
                    productFilter: .everything,
                    traits: nil,
                ),
            )
        }

        private static func registryRequirement(
            exact: Version?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> PackageDependency.Registry.Requirement {
            var candidates: [PackageDependency.Registry.Requirement] = []
            if let exact { candidates.append(.exact(exact)) }
            if let from { candidates.append(.range(from..<Version(from.major + 1, 0, 0))) }
            if let upToNextMinorFrom {
                candidates.append(
                    .range(
                        upToNextMinorFrom..<Version(upToNextMinorFrom.major, upToNextMinorFrom.minor + 1, 0),
                    ),
                )
            }
            guard let first = candidates.first else {
                throw WorkspaceOverrideAddError.registryRequiresVersionQualifier
            }
            guard candidates.count == 1 else {
                throw WorkspaceOverrideAddError.multipleVersionQualifiers
            }
            if let to {
                guard case .range(let range) = first else {
                    throw WorkspaceOverrideAddError.toRequiresRangeStart
                }
                return .range(range.lowerBound..<to)
            }
            return first
        }
    }
}

/// Errors raised while parsing arguments to a
/// `swift package workspace override add` subcommand. Cross-cuts the
/// per-source subcommands (`path`, `url`, `registry`) so the same
/// diagnostic case can surface from any of them where relevant.
enum WorkspaceOverrideAddError: Error, CustomStringConvertible {
    /// `override add url` was invoked without any of `--exact`,
    /// `--branch`, `--revision`, `--from`, or `--up-to-next-minor-from`.
    case sourceControlRequiresVersionQualifier
    /// `override add registry` was invoked without any of `--exact`,
    /// `--from`, or `--up-to-next-minor-from`.
    case registryRequiresVersionQualifier
    /// More than one version qualifier was supplied.
    case multipleVersionQualifiers
    /// `--to` was supplied without a valid range start (`--from` or
    /// `--up-to-next-minor-from`).
    case toRequiresRangeStart

    var description: String {
        switch self {
        case .sourceControlRequiresVersionQualifier:
            return "must specify one of --exact, --branch, --revision, --from, or --up-to-next-minor-from"
        case .registryRequiresVersionQualifier:
            return "must specify one of --exact, --from, or --up-to-next-minor-from"
        case .multipleVersionQualifiers:
            return "must specify at most one of --exact, --branch, --revision, --from, or --up-to-next-minor-from"
        case .toRequiresRangeStart:
            return "--to can only be specified with --from or --up-to-next-minor-from"
        }
    }
}

extension SwiftWorkspaceCommand.Override {
    /// Remove a workspace-level dependency override.
    struct Remove: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a workspace-level dependency override.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the override to remove.")
        var identity: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            try WorkspaceOverridesManager.remove(
                identity: .plain(self.identity),
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }
    }

    /// List the current workspace-level dependency overrides. Each
    /// override renders as a multi-line block in the default `text`
    /// format (identity, kind, location, and — for source-control /
    /// registry — the version requirement). `--format json` emits a
    /// machine-readable array of per-override records for downstream
    /// tooling.
    struct List: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List active workspace-level dependency overrides.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "Set the output format.")
        var format: Format = .text

        enum Format: String, ExpressibleByArgument, CaseIterable {
            case text, json
        }

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            let overrides = try WorkspaceOverridesManager.list(
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
            let rendered = try Self.renderList(overrides, format: self.format)
            print(rendered)
        }

        /// Pure renderer: produces the printable string for
        /// `overrides` in the requested format.
        ///
        /// - text: multi-line blocks per override separated by a blank
        ///   line. Empty list renders as `(no overrides declared)`.
        /// - json: JSON array of per-override records. Empty list
        ///   renders as `[]`. Version requirement (if any) is emitted
        ///   as a flat `{"kind":"exact","version":"..."}` /
        ///   `{"kind":"range","lowerBound":"...","upperBound":"..."}` /
        ///   `{"kind":"branch","value":"..."}` /
        ///   `{"kind":"revision","value":"..."}` object so downstream
        ///   consumers don't need to know the on-disk wire format.
        static func renderList(
            _ overrides: [WorkspaceOverridesJSONParser.Override],
            format: Format,
        ) throws -> String {
            switch format {
            case .text:
                return renderText(overrides)
            case .json:
                return try renderJSON(overrides)
            }
        }

        private static func renderText(
            _ overrides: [WorkspaceOverridesJSONParser.Override],
        ) -> String {
            guard !overrides.isEmpty else {
                return "(no overrides declared)"
            }
            return overrides.map(renderTextBlock).joined(separator: "\n\n")
        }

        private static func renderTextBlock(
            _ override: WorkspaceOverridesJSONParser.Override,
        ) -> String {
            let identity = override.identity.description
            let kind = overrideKindLabel(override.overridingDependency)
            let location = overrideDisplayTarget(override.overridingDependency)
            var lines = [
                identity,
                "  kind: \(kind)",
                "  location: \(location)",
            ]
            if let requirement = overrideRequirementText(override.overridingDependency) {
                lines.append("  requirement: \(requirement)")
            }
            return lines.joined(separator: "\n")
        }

        private static func renderJSON(
            _ overrides: [WorkspaceOverridesJSONParser.Override],
        ) throws -> String {
            let entries = overrides.map(jsonRecord)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(entries)
            return String(decoding: data, as: UTF8.self)
        }

        private static func jsonRecord(
            _ override: WorkspaceOverridesJSONParser.Override,
        ) -> ListEntryJSON {
            ListEntryJSON(
                identity: override.identity.description,
                kind: overrideKindLabel(override.overridingDependency),
                location: overrideDisplayTarget(override.overridingDependency),
                requirement: overrideRequirementJSON(override.overridingDependency),
            )
        }
    }
}

/// JSON wire shape for a single entry in `swift package workspace
/// override list --format json`. Codable so we can drive the encoder
/// with `.withoutEscapingSlashes` — `JSONSerialization` has no such
/// option and would escape every `/` in the location path as `\/`.
///
/// Marked `@_spi(SwiftPMInternal) public` so end-to-end tests can
/// decode into this exact type rather than duplicating the wire
/// shape into a test-local mirror. The public surface is otherwise
/// unchanged: the type is not part of libSwiftPM's client API.
@_spi(SwiftPMInternal)
public struct ListEntryJSON: Codable {
    public let identity: String
    public let kind: String
    public let location: String
    public let requirement: RequirementJSON?

    public init(
        identity: String,
        kind: String,
        location: String,
        requirement: RequirementJSON?,
    ) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.requirement = requirement
    }
}

/// JSON wire shape for a version requirement. Flat `kind + payload`
/// shape so downstream consumers don't need to know the on-disk
/// serialization format used by `WorkspaceOverridesJSONWriter`.
@_spi(SwiftPMInternal)
public enum RequirementJSON: Codable, Equatable {
    case exact(String)
    case range(lowerBound: String, upperBound: String)
    case revision(String)
    case branch(String)

    private enum CodingKeys: String, CodingKey {
        case kind, version, lowerBound, upperBound, value
    }

    private enum Kind: String {
        case exact, range, revision, branch
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exact(let version):
            try container.encode(Kind.exact.rawValue, forKey: .kind)
            try container.encode(version, forKey: .version)
        case .range(let lower, let upper):
            try container.encode(Kind.range.rawValue, forKey: .kind)
            try container.encode(lower, forKey: .lowerBound)
            try container.encode(upper, forKey: .upperBound)
        case .revision(let value):
            try container.encode(Kind.revision.rawValue, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .branch(let value):
            try container.encode(Kind.branch.rawValue, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    /// Discovers the workspace root from the command's current working
    /// directory, throwing a user-actionable error when the command
    /// is invoked outside a workspace. Common to all three
    /// subcommands.
    fileprivate static func requireWorkspaceRoot(
        _ swiftCommandState: SwiftCommandState,
    ) throws -> AbsolutePath {
        let cwd = swiftCommandState.fileSystem.currentWorkingDirectory ?? .root
        guard let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
            from: cwd,
            fileSystem: swiftCommandState.fileSystem,
        ) else {
            throw ValidationError(
                "'swift workspace override' must be invoked inside a SwiftPM workspace (no Workspace.swift found starting from \(cwd.pathString))",
            )
        }
        return workspaceRoot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "unknown requirement kind '\(kindRaw)'",
            )
        }
        switch kind {
        case .exact:
            self = .exact(try container.decode(String.self, forKey: .version))
        case .range:
            self = .range(
                lowerBound: try container.decode(String.self, forKey: .lowerBound),
                upperBound: try container.decode(String.self, forKey: .upperBound),
            )
        case .revision:
            self = .revision(try container.decode(String.self, forKey: .value))
        case .branch:
            self = .branch(try container.decode(String.self, forKey: .value))
        }
    }
}

/// Maps a `PackageDependency` case to the short kind label the list
/// command surfaces (`path` / `url` / `registry`). Rendered by both
/// the text and JSON formats so consumers see the same vocabulary.
private func overrideKindLabel(_ dep: PackageDependency) -> String {
    switch dep {
    case .fileSystem:
        return "path"
    case .sourceControl:
        return "url"
    case .registry:
        return "registry"
    case .workspaceMember, .workspaceInherited:
        // Rejected by the parser; unreachable via a valid overrides file.
        return "workspace"
    }
}

/// Formats the version requirement of a `.sourceControl` or `.registry`
/// override for the text list output. Returns `nil` for `.fileSystem`
/// overrides, which don't carry a requirement.
private func overrideRequirementText(_ dep: PackageDependency) -> String? {
    switch dep {
    case .fileSystem, .workspaceMember, .workspaceInherited:
        return nil
    case .sourceControl(let sc):
        switch sc.requirement {
        case .exact(let v): return "exact \(v)"
        case .range(let r): return "range \(r.lowerBound)..<\(r.upperBound)"
        case .revision(let s): return "revision \(s)"
        case .branch(let s): return "branch \(s)"
        }
    case .registry(let reg):
        switch reg.requirement {
        case .exact(let v): return "exact \(v)"
        case .range(let r): return "range \(r.lowerBound)..<\(r.upperBound)"
        }
    }
}

/// Serializes the version requirement of a `.sourceControl` or
/// `.registry` override as a flat JSON object. Returns `nil` for
/// `.fileSystem` overrides.
private func overrideRequirementJSON(_ dep: PackageDependency) -> RequirementJSON? {
    switch dep {
    case .fileSystem, .workspaceMember, .workspaceInherited:
        return nil
    case .sourceControl(let sc):
        switch sc.requirement {
        case .exact(let v):
            return .exact(v.description)
        case .range(let r):
            return .range(lowerBound: r.lowerBound.description, upperBound: r.upperBound.description)
        case .revision(let s):
            return .revision(s)
        case .branch(let s):
            return .branch(s)
        }
    case .registry(let reg):
        switch reg.requirement {
        case .exact(let v):
            return .exact(v.description)
        case .range(let r):
            return .range(lowerBound: r.lowerBound.description, upperBound: r.upperBound.description)
        }
    }
}

/// Discovers the workspace root from the command's current working
/// directory, throwing a user-actionable error when the command
/// is invoked outside a workspace. Common to all three
/// subcommands.
fileprivate func requireWorkspaceRoot(
    _ swiftCommandState: SwiftCommandState,
) throws -> AbsolutePath {
    let cwd = swiftCommandState.fileSystem.currentWorkingDirectory ?? .root
    guard let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
        from: cwd,
        fileSystem: swiftCommandState.fileSystem,
    ) else {
        throw ValidationError(
            "'swift package workspace override' must be invoked inside a SwiftPM workspace (no Workspace.swift found starting from \(cwd.pathString))",
        )
    }
    return workspaceRoot
}

/// Renders the target of an override for the `list` output. Uses the
/// underlying kind's most user-facing location (file path, URL, or
/// registry identifier) — avoids depending on
/// `PackageDependency.locationString`, which is internal to the
/// Workspace module.
private func overrideDisplayTarget(_ dep: PackageDependency) -> String {
    switch dep {
    case .fileSystem(let fs):
        return fs.path.pathString
    case .sourceControl(let sc):
        switch sc.location {
        case .local(let abs):
            return abs.pathString
        case .remote(let url):
            return url.absoluteString
        }
    case .registry(let reg):
        return reg.identity.description
    case .workspaceMember, .workspaceInherited:
        // Rejected by the parser; unreachable via a valid overrides file.
        return "<workspace-scoped>"
    }
}
