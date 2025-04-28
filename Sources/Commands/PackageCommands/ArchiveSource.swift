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
import PackageGraph
import PackageModel
import SourceControl

extension SwiftPackageCommand {
    struct ArchiveSource: AsyncSwiftCommand {
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

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let packageDirectory = try globalOptions.locations.packageDirectory ?? swiftCommandState.getPackageRoot()

            let archivePath: AbsolutePath
            if let output {
                archivePath = output
            } else {
                let graph = try await swiftCommandState.loadPackageGraph()
                let packageName = graph.rootPackages[graph.rootPackages.startIndex].manifest.displayName // TODO: use identity instead?
                archivePath = packageDirectory.appending("\(packageName).zip")
            }

            try await SwiftPackageCommand.archiveSource(
                at: packageDirectory,
                to: archivePath,
                fileSystem: localFileSystem,
                cancellator: swiftCommandState.cancellator
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
    ) async throws {
        let gitRepositoryProvider = GitRepositoryProvider()
        if (try? gitRepositoryProvider.isValidDirectory(packageDirectory)) == true {
            let repository = GitRepository(path: packageDirectory, cancellator: cancellator)
            try repository.archive(to: archivePath)
        } else {
            let zipArchiver = ZipArchiver(fileSystem: fileSystem, cancellator: cancellator)
            try await zipArchiver.compress(directory: packageDirectory, to: archivePath)
        }
    }
}
