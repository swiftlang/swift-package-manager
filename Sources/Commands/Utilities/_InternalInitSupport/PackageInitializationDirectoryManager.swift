
import Basics


import Workspace
import Foundation
import CoreCommands


public struct TemplateInitializationDirectoryManager {
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

    public func cleanupTemporary(templateSource: InitTemplatePackage.TemplateSource, path: Basics.AbsolutePath, temporaryDirectory: Basics.AbsolutePath?) throws {
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

            if let tempDir = temporaryDirectory {
                try fileSystem.removeFileTree(tempDir)
            }

        } catch {
            throw CleanupError.failedToCleanup(temporaryDirectory: temporaryDirectory, underlying: error)
        }
    }

    enum CleanupError: Error, CustomStringConvertible {
        case failedToCleanup(temporaryDirectory: Basics.AbsolutePath?, underlying: Error)

        var description: String {
            switch self {
            case .failedToCleanup(let temporaryDirectory, let error):
                let tempDir = temporaryDirectory?.pathString ?? "<no temporary directory initialized>"
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
