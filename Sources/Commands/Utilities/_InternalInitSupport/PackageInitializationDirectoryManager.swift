
import Basics

@_spi(SwiftPMInternal)

import Workspace
import SPMBuildCore
import TSCBasic
import Foundation
import CoreCommands

struct TemplateInitializationDirectoryManager {
    let fileSystem: FileSystem

    func createTemporaryDirectories() throws -> (Basics.AbsolutePath, Basics.AbsolutePath, Basics.AbsolutePath) {
        let tempRoot = try fileSystem.tempDirectory.appending(component: UUID().uuidString)
        let stagingPath = tempRoot.appending(component: "generated-package")
        let cleanupPath = tempRoot.appending(component: "clean-up")
        try fileSystem.createDirectory(tempRoot)
        return (stagingPath, cleanupPath, tempRoot)
    }

    func finalize(
        cwd: Basics.AbsolutePath,
        stagingPath: Basics.AbsolutePath,
        cleanupPath: Basics.AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) async throws {
        if fileSystem.exists(cwd) {
            try fileSystem.removeFileTree(cwd)
        }
        try fileSystem.copy(from: stagingPath, to: cleanupPath)
        _ = try await swiftCommandState.withTemporaryWorkspace(switchingTo: cleanupPath) { _, _ in
            try SwiftPackageCommand.Clean().run(swiftCommandState)
        }
        try fileSystem.copy(from: cleanupPath, to: cwd)
    }

    func cleanupTemporary(templateSource: InitTemplatePackage.TemplateSource, path: Basics.AbsolutePath, tempDir: Basics.AbsolutePath) throws {
        switch templateSource {
        case .git:
            try? FileManager.default.removeItem(at: path.asURL)
        case .registry:
            try? FileManager.default.removeItem(at: path.parentDirectory.asURL)
        default:
            break
        }
        try? fileSystem.removeFileTree(tempDir)
    }
}
