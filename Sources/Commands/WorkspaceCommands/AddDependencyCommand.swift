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
import TSCUtility
import struct PackageModel.WorkspaceManifest

extension SwiftWorkspaceCommand {
    /// Adds a package dependency to the enclosing workspace's
    /// `Workspace.swift`. Workspace-level counterpart to
    /// `swift package add-dependency`, differing in two ways:
    /// (1) the manifest target is `Workspace.swift`'s workspace-level
    /// `dependencies:` (members reach the dep via
    /// `.package(workspaceInherited:)`), and (2) the dependency source
    /// is a **subcommand** rather than a `--type` flag — matching the
    /// shape established by `swift workspace override add {path,url,registry}`
    /// so Argument Parser structurally enforces the mutual exclusion
    /// (e.g. `--branch` never appears on the `path` subcommand's help).
    struct AddDependency: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add-dependency",
            abstract: "Add a package dependency to this workspace's Workspace.swift.",
            subcommands: [Path.self, Url.self, Registry.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )
    }
}

extension SwiftWorkspaceCommand.AddDependency {
    /// Adds a `.package(path: ...)` entry to the workspace's
    /// `dependencies:`. Relative paths are stored verbatim; SwiftPM
    /// resolves them against the workspace root at load time.
    struct Path: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Add a local filesystem dependency.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The local filesystem path of the package to add.")
        var path: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift workspace add-dependency path",
            )
            let expression = Self.renderExpression(path: self.path)
            try applyWorkspaceDependencyEdit(
                expression: expression,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure renderer: composes the `.package(path: "...")`
        /// expression that gets appended to `dependencies:`. Exposed
        /// for unit tests.
        static func renderExpression(path: String) -> String {
            #".package(path: "\#(path)")"#
        }
    }

    /// Adds a `.package(url: ..., <requirement>)` entry to the
    /// workspace's `dependencies:`. Exactly one of the version
    /// qualifiers (`--exact`, `--branch`, `--revision`, `--from`,
    /// `--up-to-next-minor-from`) must be supplied. `--to` pairs
    /// with `--from` or `--up-to-next-minor-from` to bound the
    /// upper end of the range.
    struct Url: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "url",
            abstract: "Add a source-control dependency.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The source-control URL of the package to add.")
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
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift workspace add-dependency url",
            )
            let expression = try Self.renderExpression(
                url: self.url,
                exact: self.exact,
                branch: self.branch,
                revision: self.revision,
                from: self.from,
                upToNextMinorFrom: self.upToNextMinorFrom,
                to: self.to,
            )
            try applyWorkspaceDependencyEdit(
                expression: expression,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure renderer: composes the `.package(url: ...)`
        /// expression that gets appended to `dependencies:`. Throws
        /// when zero or multiple version qualifiers are set, or when
        /// `--to` is supplied without a valid range start.
        static func renderExpression(
            url: String,
            exact: Version?,
            branch: String?,
            revision: String?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> String {
            let requirement = try renderSourceControlRequirement(
                exact: exact,
                branch: branch,
                revision: revision,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to,
            )
            return #".package(url: "\#(url)", \#(requirement))"#
        }
    }

    /// Adds a `.package(id: ..., <requirement>)` entry to the
    /// workspace's `dependencies:`, resolved via the package
    /// registry. Exactly one of the version qualifiers
    /// (`--exact`, `--from`, `--up-to-next-minor-from`) must be
    /// supplied — branch and revision are rejected because the
    /// registry requirement doesn't support them. `--to` pairs with
    /// `--from` or `--up-to-next-minor-from` to bound the upper
    /// end of the range.
    struct Registry: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "registry",
            abstract: "Add a registry-resolved dependency.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The registry identity of the package to add.")
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
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift workspace add-dependency registry",
            )
            let expression = try Self.renderExpression(
                identity: self.identity,
                exact: self.exact,
                from: self.from,
                upToNextMinorFrom: self.upToNextMinorFrom,
                to: self.to,
            )
            try applyWorkspaceDependencyEdit(
                expression: expression,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }

        /// Pure renderer: composes the `.package(id: ...)`
        /// expression that gets appended to `dependencies:`.
        static func renderExpression(
            identity: String,
            exact: Version?,
            from: Version?,
            upToNextMinorFrom: Version?,
            to: Version?,
        ) throws -> String {
            let requirement = try renderRegistryRequirement(
                exact: exact,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to,
            )
            return #".package(id: "\#(identity)", \#(requirement))"#
        }
    }
}

/// Errors raised while parsing arguments to a
/// `swift workspace add-dependency <sub>` subcommand. Shared across
/// the per-source subcommands so the same diagnostic vocabulary as
/// `override add` surfaces here.
enum WorkspaceAddDependencyError: Error, CustomStringConvertible {
    /// `add-dependency url` was invoked without any of `--exact`,
    /// `--branch`, `--revision`, `--from`, or `--up-to-next-minor-from`.
    case sourceControlRequiresVersionQualifier
    /// `add-dependency registry` was invoked without any of `--exact`,
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

/// Reads `Workspace.swift` at `workspaceRoot`, applies the syntax
/// edit that appends `expression` to the `dependencies:` array,
/// and writes the result back. No-op when the manifest already
/// contains a byte-identical `.package(...)` entry.
private func applyWorkspaceDependencyEdit(
    expression: String,
    workspaceRoot: AbsolutePath,
    fileSystem: any FileSystem,
) throws {
    let manifestPath = workspaceRoot.appending(WorkspaceManifest.filename)
    let source: String = try fileSystem.readFileContents(manifestPath)
    let editedSource = try WorkspaceManifestSyntax.addDependency(
        expression,
        to: source,
    )
    if editedSource != source {
        try fileSystem.writeFileContents(manifestPath, string: editedSource)
    }
}

/// Renders the version-requirement label + value pair for a
/// source-control (`.package(url:...)`) dependency: `exact:`,
/// `branch:`, `revision:`, `from:`, or a
/// `"lowerBound"..<"upperBound"` range built from `--from` or
/// `--up-to-next-minor-from` combined with `--to`.
private func renderSourceControlRequirement(
    exact: Version?,
    branch: String?,
    revision: String?,
    from: Version?,
    upToNextMinorFrom: Version?,
    to: Version?,
) throws -> String {
    var candidates: [String] = []
    if let exact { candidates.append(#"exact: "\#(exact.description)""#) }
    if let branch { candidates.append(#"branch: "\#(branch)""#) }
    if let revision { candidates.append(#"revision: "\#(revision)""#) }
    if let from { candidates.append(#"from: "\#(from.description)""#) }
    if let upToNextMinorFrom {
        let upper: Version = to ?? Version(
            upToNextMinorFrom.major,
            upToNextMinorFrom.minor + 1,
            0,
        )
        candidates.append(
            #""\#(upToNextMinorFrom.description)"..<"\#(upper.description)""#,
        )
    }

    if candidates.count > 1 {
        throw WorkspaceAddDependencyError.multipleVersionQualifiers
    }
    guard let first = candidates.first else {
        throw WorkspaceAddDependencyError.sourceControlRequiresVersionQualifier
    }
    if let to, from != nil {
        return #""\#(from!.description)"..<"\#(to.description)""#
    }
    if to != nil, from == nil, upToNextMinorFrom == nil {
        throw WorkspaceAddDependencyError.toRequiresRangeStart
    }
    return first
}

/// Renders the version-requirement label + value pair for a
/// registry (`.package(id:...)`) dependency. Same shape as
/// `renderSourceControlRequirement` minus the source-control-specific
/// `branch:` / `revision:` options.
private func renderRegistryRequirement(
    exact: Version?,
    from: Version?,
    upToNextMinorFrom: Version?,
    to: Version?,
) throws -> String {
    var candidates: [String] = []
    if let exact { candidates.append(#"exact: "\#(exact.description)""#) }
    if let from { candidates.append(#"from: "\#(from.description)""#) }
    if let upToNextMinorFrom {
        let upper: Version = to ?? Version(
            upToNextMinorFrom.major,
            upToNextMinorFrom.minor + 1,
            0,
        )
        candidates.append(
            #""\#(upToNextMinorFrom.description)"..<"\#(upper.description)""#,
        )
    }

    if candidates.count > 1 {
        throw WorkspaceAddDependencyError.multipleVersionQualifiers
    }
    guard let first = candidates.first else {
        throw WorkspaceAddDependencyError.registryRequiresVersionQualifier
    }
    if let to, from != nil {
        return #""\#(from!.description)"..<"\#(to.description)""#
    }
    if to != nil, from == nil, upToNextMinorFrom == nil {
        throw WorkspaceAddDependencyError.toRequiresRangeStart
    }
    return first
}
