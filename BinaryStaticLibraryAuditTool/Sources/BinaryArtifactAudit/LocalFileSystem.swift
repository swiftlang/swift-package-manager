private import Foundation
package import SystemPackage

package struct LocalFileSystem: FileSystem {
    package init() { }

    package func fileInfo(_ path: FilePath) throws -> FileInfo {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.string)
        let type = attributes[.type] as? FileAttributeType ?? .typeUnknown
        return FileInfo(type: type)
    }

    package func createTemporaryDirectory() throws -> FilePath {
        let temporaryDirectoryPath = FilePath(FileManager.default.temporaryDirectory.path).appending(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: temporaryDirectoryPath.string, withIntermediateDirectories: true)
        return temporaryDirectoryPath
    }
}
