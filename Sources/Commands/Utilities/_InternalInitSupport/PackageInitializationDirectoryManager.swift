//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import CoreCommands
import Foundation
import Workspace

import Basics
import CoreCommands
import Foundation
import PackageModel

public struct TemplateInitializationDirectoryManager {
    let observabilityScope: ObservabilityScope
    let fileSystem: FileSystem
    let helper: TemporaryDirectoryHelper

    public init(fileSystem: FileSystem, observabilityScope: ObservabilityScope) {
        self.fileSystem = fileSystem
        self.helper = TemporaryDirectoryHelper(fileSystem: fileSystem)
        self.observabilityScope = observabilityScope
    }

    public func createTemporaryDirectories() throws
        -> (stagingPath: Basics.AbsolutePath, cleanupPath: Basics.AbsolutePath, tempDir: Basics.AbsolutePath)
    {
        let tempDir = try helper.createTemporaryDirectory()
        let dirs = try helper.createSubdirectories(in: tempDir, names: ["generated-package", "clean-up"])

        return (dirs[0], dirs[1], tempDir)
    }

    public func finalize(
        cwd: Basics.AbsolutePath,
        stagingPath: Basics.AbsolutePath,
        cleanupPath: Basics.AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) async throws {
        try self.helper.copyDirectoryContents(from: stagingPath, to: cleanupPath)
        try await self.cleanBuildArtifacts(at: cleanupPath, swiftCommandState: swiftCommandState)
        try self.helper.copyDirectoryContents(from: cleanupPath, to: cwd)
    }

    func cleanBuildArtifacts(at path: Basics.AbsolutePath, swiftCommandState: SwiftCommandState) async throws {
        _ = try await swiftCommandState.withTemporaryWorkspace(switchingTo: path) { _, _ in
            try SwiftPackageCommand.Clean().run(swiftCommandState)
        }
    }

    public func cleanupTemporary(
        templateSource: InitTemplatePackage.TemplateSource,
        path: Basics.AbsolutePath,
        temporaryDirectory: Basics.AbsolutePath?
    ) throws {
        do {
            switch templateSource {
            case .git, .registry:
                do {
                    try FileManager.default.removeItem(at: path.asURL)
                } catch {
                    // Fallback: remove contents individually if folder deletion fails
                    let contents = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
                    for item in contents {
                        let itemURL = path.appending(item).asURL
                        try FileManager.default.removeItem(at: itemURL)
                    }
                }
            case .local:
                break
            }

            if let tempDir = temporaryDirectory {
                try self.helper.removeDirectoryIfExists(tempDir)
            }
        } catch {
            throw DirectoryManagerError.cleanupFailed(path: temporaryDirectory)
        }
    }
}
