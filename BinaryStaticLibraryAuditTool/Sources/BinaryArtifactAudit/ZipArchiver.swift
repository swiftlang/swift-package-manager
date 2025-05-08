private import Foundation
internal import SystemPackage

struct ZipArchiver {
    static func extract(
        from archivePath: FilePath,
        to destinationPath: FilePath
    ) async throws {
        let fileSystem = LocalFileSystem()
        guard fileSystem.isRegularFile(archivePath) else {
            throw Err.noEntry(archivePath)
        }

        guard fileSystem.isDirectory(destinationPath) else {
            throw Err.noEntry(destinationPath)
        }

        try await Process.run(executable: FilePath("/usr/bin/unzip"), arguments: archivePath.string, "-d", destinationPath.string)
    }
}

extension ZipArchiver{
    enum Err: Error {
        case noEntry(FilePath)
    }
}
