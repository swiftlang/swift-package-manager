internal import BinaryArtifactAudit

private import Foundation
internal import SystemPackage

final class VirtualFileSystem: FileSystem {
    var root: Node = Node(name: "", kind: .directory(children: [.init(name: "tmp", kind: .directory(children: []))]))
    var currentWorkingDirectory: FilePath = "/"

    func fileInfo(_ path: FilePath) throws -> FileInfo {
        let node = try find(path)

        switch node.kind {
        case .directory(_):
            return FileInfo(type: .typeDirectory)
        case .regularFile:
            return FileInfo(type: .typeRegular)
        }
    }

    func createTemporaryDirectory() throws -> FilePath {
        let tmpDirPath = FilePath("/tmp")
        let tmpDir = try find(tmpDirPath)
        guard case .directory(var children) = tmpDir.kind else {
            throw Err.unexpectedRegularFile("/tmp")
        }

        let name = UUID().uuidString
        children.append(.init(name: name, kind: .directory(children: [])))

        tmpDir.kind = .directory(children: children)

        return tmpDirPath.appending(name)
    }

    private func find(_ path: FilePath) throws -> Node {
        var currentPath = FilePath("/")
        var currentNode = root

        for component in currentWorkingDirectory.pushing(path).components {
            guard case .directory(let children) = currentNode.kind else {
                throw Err.unexpectedRegularFile(currentPath.string)
            }

            currentPath.append(component)

            guard let child = children.first(where: { $0.name == component.string }) else {
                throw Err.noSuchEntry(currentPath.string)
            }

            currentNode = child
        }

        return currentNode
    }
}

extension VirtualFileSystem {
    final class Node {
        enum Kind {
            case regularFile
            case directory(children: [Node])
        }

        let name: String
        var kind: Kind

        fileprivate init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }
    }
}

extension VirtualFileSystem {
    enum Err: Error {
        case noSuchEntry(String)
        case unexpectedRegularFile(String)
    }
}
