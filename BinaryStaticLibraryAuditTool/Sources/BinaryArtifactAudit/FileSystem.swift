package import SystemPackage

package protocol FileSystem {
    func fileInfo(_ path: FilePath) throws -> FileInfo

    func isRegularFile(_ path: FilePath) -> Bool

    func isDirectory(_ path: FilePath) -> Bool

    func createTemporaryDirectory() throws -> FilePath
}

extension FileSystem {
    package func isRegularFile(_ path: FilePath) -> Bool {
        do {
            return try fileInfo(path).isRegularFile
        } catch {
            return false
        }
    }

    package func isDirectory(_ path: FilePath) -> Bool {
        do {
            return try fileInfo(path).isDirectory
        } catch {
            return false
        }
    }
}
