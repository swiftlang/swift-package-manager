//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import SourceControl
import TSCBasic

extension SwiftPackageTool {
    struct ArchiveSource: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "archive-source",
            abstract: "Create a source archive for the package"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(
            name: [.short, .long],
            help: "The absolute or relative path for the generated source archive"
        )
        var output: AbsolutePath?

        func run(_ swiftTool: SwiftTool) throws {
            let packageDirectory = try globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()

            let archivePath: AbsolutePath
            if let output {
                archivePath = output
            } else {
                let graph = try swiftTool.loadPackageGraph()
                let packageName = graph.rootPackages[0].manifest.displayName // TODO: use identity instead?
                archivePath = packageDirectory.appending("\(packageName).zip")
            }

            try SwiftPackageTool.archiveSource(
                at: packageDirectory,
                to: archivePath,
                fileSystem: localFileSystem,
                cancellator: swiftTool.cancellator
            )

            if archivePath.isDescendantOfOrEqual(to: packageDirectory) {
                let relativePath = archivePath.relative(to: packageDirectory)
                print("Created \(relativePath.pathString)")
            } else {
                print("Created \(archivePath.pathString)")
            }
        }
    }

    public static func archiveSource(
        at packageDirectory: AbsolutePath,
        to archivePath: AbsolutePath,
        fileSystem: FileSystem,
        cancellator: Cancellator?
    ) throws  {
        let gitRepositoryProvider = GitRepositoryProvider()
        if gitRepositoryProvider.repositoryExists(at: packageDirectory) {
            let repository = GitRepository(path: packageDirectory, cancellator: cancellator)
            try repository.archive(to: archivePath)
        } else {
            let zipArchiver = ZipArchiver(fileSystem: fileSystem, cancellator: cancellator)
            try tsc_await {
                zipArchiver.compress(directory: packageDirectory, to: archivePath, completion: $0)
            }
        }
    }
}
