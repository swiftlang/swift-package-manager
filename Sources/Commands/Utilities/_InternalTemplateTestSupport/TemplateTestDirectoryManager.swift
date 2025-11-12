import Basics
import CoreCommands
import Foundation
import PackageModel
import Workspace

/// Manages directories for template testing operations.
public struct TemplateTestingDirectoryManager {
    let fileSystem: FileSystem
    let helper: TemporaryDirectoryHelper
    let observabilityScope: ObservabilityScope

    public init(fileSystem: FileSystem, observabilityScope: ObservabilityScope) {
        self.fileSystem = fileSystem
        self.helper = TemporaryDirectoryHelper(fileSystem: fileSystem)
        self.observabilityScope = observabilityScope
    }

    /// Creates temporary directories for testing operations.
    public func createTemporaryDirectories(directories: Set<String>) throws -> [Basics.AbsolutePath] {
        let tempDir = try helper.createTemporaryDirectory()
        return try self.helper.createSubdirectories(in: tempDir, names: Array(directories))
    }

    /// Creates the output directory for test results.
    public func createOutputDirectory(
        outputDirectoryPath: Basics.AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) throws {
        let manifestPath = outputDirectoryPath.appending(component: Manifest.filename)
        let fs = swiftCommandState.fileSystem

        if !self.helper.directoryExists(outputDirectoryPath) {
            try fileSystem.createDirectory(outputDirectoryPath)
        } else if fs.exists(manifestPath) {
            self.observabilityScope.emit(
                error: DirectoryManagerError.foundManifestFile(path: outputDirectoryPath)
            )
            throw DirectoryManagerError.foundManifestFile(path: outputDirectoryPath)
        }
    }
}
