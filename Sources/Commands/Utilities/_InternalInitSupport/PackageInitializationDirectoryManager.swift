
import Basics


import Workspace
import Foundation
import CoreCommands


struct TemplateInitializationDirectoryManager {
    let fileSystem: FileSystem

    func createTemporaryDirectories() throws -> (stagingPath: Basics.AbsolutePath, cleanUpPath: Basics.AbsolutePath, tempDir: Basics.AbsolutePath) {
        let tempDir = try fileSystem.tempDirectory.appending(component: UUID().uuidString)
        let stagingPath = tempDir.appending(component: "generated-package")
        let cleanupPath = tempDir.appending(component: "clean-up")
        try fileSystem.createDirectory(tempDir)
        return (stagingPath, cleanupPath, tempDir)
    }

    func finalize(
        cwd: Basics.AbsolutePath,
        stagingPath: Basics.AbsolutePath,
        cleanupPath: Basics.AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) async throws {
        if fileSystem.exists(cwd) {
            do {
                try fileSystem.removeFileTree(cwd)
            } catch {
                throw FileOperationError.failedToRemoveExistingDirectory(path: cwd, underlying: error)
            }
        }
        try fileSystem.copy(from: stagingPath, to: cleanupPath)
        try await cleanBuildArtifacts(at: cleanupPath, swiftCommandState: swiftCommandState)
        try fileSystem.copy(from: cleanupPath, to: cwd)
    }

    func cleanBuildArtifacts(at path: Basics.AbsolutePath, swiftCommandState: SwiftCommandState) async throws {
        _ = try await swiftCommandState.withTemporaryWorkspace(switchingTo: path) { _, _ in
            try SwiftPackageCommand.Clean().run(swiftCommandState)
        }
    }

    func cleanupTemporary(templateSource: InitTemplatePackage.TemplateSource, path: Basics.AbsolutePath, tempDir: Basics.AbsolutePath) throws {
        do {
            switch templateSource {
            case .git:
                if FileManager.default.fileExists(atPath: path.pathString) {
                    try FileManager.default.removeItem(at: path.asURL)
                }
            case .registry:
                if FileManager.default.fileExists(atPath: path.pathString) {
                    try FileManager.default.removeItem(at: path.asURL)
                }
            case .local:
                break
            }
            try fileSystem.removeFileTree(tempDir)
        } catch {
            throw CleanupError.failedToCleanup(tempDir: tempDir, underlying: error)
        }
    }

    enum CleanupError: Error, CustomStringConvertible {
        case failedToCleanup(tempDir: Basics.AbsolutePath, underlying: Error)

        var description: String {
            switch self {
            case .failedToCleanup(let tempDir, let error):
                return "Failed to clean up temporary directory at \(tempDir): \(error.localizedDescription)"
            }
        }
    }

    enum FileOperationError: Error, CustomStringConvertible {
        case failedToRemoveExistingDirectory(path: Basics.AbsolutePath, underlying: Error)

        var description: String {
            switch self {
            case .failedToRemoveExistingDirectory(let path, let underlying):
                return "Failed to remove existing directory at \(path): \(underlying.localizedDescription)"
            }
        }
    }

}
