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
import PackageModel
import Workspace


extension SwiftWorkspaceCommand {
    /// Adds a new member entry to the enclosing workspace's
    /// `Workspace.swift`. Idempotent — a duplicate `path` leaves the
    /// manifest byte-identical. With `--scaffold`, also creates the
    /// member's directory and a stub `Package.swift` when they don't
    /// already exist, mirroring `swift workspace init
    /// --members`.
    struct AddMember: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "add-member",
            abstract: "Add a new member to this workspace's Workspace.swift.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The member path (relative to the workspace root).")
        var path: String

        @Option(
            name: .customLong("scaffold"),
            help: "Also create the member directory and scaffold a \(Manifest.filename) of the given type (\(InitPackage.PackageType.allCases.map { $0.rawValue }.joined(separator: ", "))) when missing.",
        )
        var scaffold: InitPackage.PackageType?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift workspace add-member",
            )
            let manifestPath = workspaceRoot.appending(WorkspaceManifest.filename)
            let fileSystem = swiftCommandState.fileSystem
            let source: String = try fileSystem.readFileContents(manifestPath)
            let editedSource = try WorkspaceManifestSyntax.addMember(self.path, to: source)
            if editedSource != source {
                try fileSystem.writeFileContents(manifestPath, string: editedSource)
            }

            if let packageType = self.scaffold {
                let memberDir = workspaceRoot.appending(try RelativePath(validating: self.path))
                let memberManifest = memberDir.appending(Manifest.filename)
                let shouldScaffold = Self.shouldScaffoldMemberPackage(
                    memberPath: self.path,
                    memberManifest: memberManifest,
                    fileSystem: fileSystem,
                    observabilityScope: swiftCommandState.observabilityScope,
                )
                if shouldScaffold {
                    if !fileSystem.exists(memberDir) {
                        try fileSystem.createDirectory(memberDir, recursive: true)
                    }
                    let init_ = try InitPackage(
                        name: memberDir.basename,
                        options: .init(
                            packageType: packageType,
                            supportedTestingLibraries: [.swiftTesting],
                        ),
                        destinationPath: memberDir,
                        installedSwiftPMConfiguration: .default,
                        fileSystem: fileSystem,
                    )
                    init_.progressReporter = { print($0) }
                    try init_.writePackageStructure()
                }
            }
        }

        /// Pure decision: given the target member's manifest location,
        /// decides whether `--scaffold` should proceed. Returns `true`
        /// when the file does not exist yet. When it already exists,
        /// emits `.scaffoldIgnoredMemberAlreadyExists` and returns
        /// `false` so the caller leaves the pre-existing manifest
        /// byte-identical.
        static func shouldScaffoldMemberPackage(
            memberPath: String,
            memberManifest: AbsolutePath,
            fileSystem: any FileSystem,
            observabilityScope: ObservabilityScope,
        ) -> Bool {
            if fileSystem.exists(memberManifest) {
                observabilityScope.emit(
                    .scaffoldIgnoredMemberAlreadyExists(memberPath: memberPath),
                )
                return false
            }
            return true
        }
    }
}


extension Basics.Diagnostic {
    /// Diagnostic emitted when `swift workspace add-member
    /// <path> --scaffold <type>` is invoked but the member's
    /// `Package.swift` already exists. The manifest edit still
    /// happens; only the scaffolding is skipped, so this is a
    /// warning rather than an error.
    @_spi(SwiftPMInternal)
    public static func scaffoldIgnoredMemberAlreadyExists(memberPath: String) -> Self {
        .warning(
            "'--scaffold' ignored: \(memberPath)/\(Manifest.filename) already exists",
        )
    }
}
