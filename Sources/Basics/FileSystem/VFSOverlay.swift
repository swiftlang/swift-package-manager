//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.JSONEncoder

public struct VFSOverlay: Encodable {

    public class Resource: Encodable {
        private let name: String
        private let type: String

        fileprivate init(name: String, type: String) {
            self.name = name
            self.type = type
        }
    }

    public class File: Resource {
        private enum CodingKeys: String, CodingKey {
            case externalContents = "external-contents"
        }

        private let externalContents: String

        public init(name: String, externalContents: String) {
            self.externalContents = externalContents
            super.init(name: name, type: "file")
        }

        public override func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(externalContents, forKey: .externalContents)
            try super.encode(to: encoder)
        }
    }

    public class Directory: Resource {
        private enum CodingKeys: CodingKey {
            case contents
        }

        private let contents: [Resource]

        public init(name: String, contents: [Resource]) {
            self.contents = contents
            super.init(name: name, type: "directory")
        }

        public override func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(contents, forKey: .contents)
            try super.encode(to: encoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case roots
        case useExternalNames = "use-external-names"
        case caseSensitive = "case-sensitive"
        case version
    }

    private let roots: [Resource]
    private let useExternalNames = false
    private let caseSensitive = false
    private let version = 0

    public init(roots: [File]) {
        self.roots = roots
    }

    public init(roots: [Directory]) {
        self.roots = roots
    }

    public func write(to path: AbsolutePath, fileSystem: FileSystem) throws {
        // VFS overlay files are YAML, but ours is simple enough that it works when being written using `JSONEncoder`.
        try JSONEncoder.makeWithDefaults(prettified: false).encode(path: path, fileSystem: fileSystem, self)
    }
}

public extension VFSOverlay {
    /// Returns a tree of `VFSOverlay` resources for a given directory in the form of an array. Each item
    /// in this array will be a resource (either file or directory) from the top most level of the given directory.
    /// - Parameters:
    ///   - directoryPath: The directory to recursively search for resources in.
    ///   - fileSystem: The file system to search.
    /// - Returns: An array of `VFSOverlay.Resource`s from the given directory.
    /// - Throws: An error if the given path is a not a directory.
    /// - Note: This API will recursively scan all subpaths of the given path.
    static func overlayResources(
        directoryPath: AbsolutePath,
        fileSystem: FileSystem
    ) throws -> [VFSOverlay.Resource] {
        return
            // Absolute path to each resource in the directory.
            try fileSystem.getDirectoryContents(directoryPath).map(directoryPath.appending(component:))
            // Map each path to a corresponding VFSOverlay, recursing for directories.
            .compactMap { resourcePath in
                if fileSystem.isDirectory(resourcePath) {
                    return VFSOverlay.Directory(
                        name: resourcePath.basename,
                        contents:
                            try overlayResources(
                                directoryPath: resourcePath,
                                fileSystem: fileSystem
                            )
                    )
                } else if fileSystem.isFile(resourcePath) {
                    return VFSOverlay.File(
                        name: resourcePath.basename,
                        externalContents: resourcePath.pathString
                    )
                } else {
                    // This case is not expected to be reached as a resource
                    // should be either a file or directory.
                    return nil
                }
            }
    }
}
