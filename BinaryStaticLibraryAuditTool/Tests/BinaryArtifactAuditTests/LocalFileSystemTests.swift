internal import Testing
private import BinaryArtifactAudit
private import Foundation

@Suite
struct LocalFileSystemTests {
    @Test
    func createTemporaryDirectory() throws {
        let fileSystem = LocalFileSystem()
        let temporary = try fileSystem.createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: temporary.string) }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: temporary.string, isDirectory: &isDirectory)
        #expect(exists && isDirectory.boolValue)

    }

    @Test
    func regularFileExists() throws {
        let fileSystem = LocalFileSystem()
        #expect(fileSystem.isRegularFile(#filePath))
    }
}
