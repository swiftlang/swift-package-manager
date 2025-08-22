import Basics
import Workspace
import Foundation
import CoreCommands


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

    public func createTemporaryDirectories() throws -> (stagingPath: Basics.AbsolutePath, cleanupPath: Basics.AbsolutePath, tempDir: Basics.AbsolutePath) {
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
        try helper.copyDirectoryContents(from: stagingPath, to: cleanupPath)
        try await cleanBuildArtifacts(at: cleanupPath, swiftCommandState: swiftCommandState)
        try helper.copyDirectoryContents(from: cleanupPath, to: cwd)
    }

    func cleanBuildArtifacts(at path: Basics.AbsolutePath, swiftCommandState: SwiftCommandState) async throws {
        _ = try await swiftCommandState.withTemporaryWorkspace(switchingTo: path) { _, _ in
            try SwiftPackageCommand.Clean().run(swiftCommandState)
        }
    }

    public func cleanupTemporary(templateSource: InitTemplatePackage.TemplateSource, path: Basics.AbsolutePath, temporaryDirectory: Basics.AbsolutePath?) throws {
        do {
            switch templateSource {
            case .git, .registry:
                if FileManager.default.fileExists(atPath: path.pathString) {
                    try FileManager.default.removeItem(at: path.asURL)
                }
            case .local:
                break
            }

            if let tempDir = temporaryDirectory {
                try helper.removeDirectoryIfExists(tempDir)
            }

        } catch {
            observabilityScope.emit(
                error: DirectoryManagerError.cleanupFailed(path: temporaryDirectory, underlying: error),
                underlyingError: error
            )
            throw DirectoryManagerError.cleanupFailed(path: temporaryDirectory, underlying: error)
        }
    }
}
