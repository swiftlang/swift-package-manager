import Basics
import CoreCommands
import Foundation
import Workspace
import PackageModel

public struct TemplateTestingDirectoryManager {
    let fileSystem: FileSystem
    let helper: TemporaryDirectoryHelper
    let observabilityScope: ObservabilityScope

    public init(fileSystem: FileSystem, observabilityScope: ObservabilityScope) {
        self.fileSystem = fileSystem
        self.helper = TemporaryDirectoryHelper(fileSystem: fileSystem)
        self.observabilityScope = observabilityScope
    }

    public func createTemporaryDirectories(directories: Set<String>) throws -> [Basics.AbsolutePath] {
        let tempDir = try helper.createTemporaryDirectory()
        return try helper.createSubdirectories(in: tempDir, names: Array(directories))
    }

    public func createOutputDirectory(outputDirectoryPath: Basics.AbsolutePath, swiftCommandState: SwiftCommandState) throws {
        let manifestPath = outputDirectoryPath.appending(component: Manifest.filename)
        let fs = swiftCommandState.fileSystem

        if !helper.directoryExists(outputDirectoryPath) {
            try FileManager.default.createDirectory(
                at: outputDirectoryPath.asURL,
                withIntermediateDirectories: true
            )
        } else if fs.exists(manifestPath) {
            observabilityScope.emit(
                error: DirectoryManagerError.foundManifestFile(path: outputDirectoryPath)
            )
            throw DirectoryManagerError.foundManifestFile(path: outputDirectoryPath)
        }
    }
}
