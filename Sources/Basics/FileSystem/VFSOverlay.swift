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
    public struct File: Encodable {
        enum CodingKeys: String, CodingKey {
            case externalContents = "external-contents"
            case name
            case type
        }

        private let externalContents: String
        private let name: String
        private let type = "file"

        public init(name: String, externalContents: String) {
            self.name = name
            self.externalContents = externalContents
        }
    }

    enum CodingKeys: String, CodingKey {
        case roots
        case useExternalNames = "use-external-names"
        case version
    }

    private let roots: [File]
    private let useExternalNames = false
    private let version = 0

    public init(roots: [File]) {
        self.roots = roots
    }

    public func write(to path: AbsolutePath, fileSystem: FileSystem) throws {
        // VFS overlay files are YAML, but ours is simple enough that it works when being written using `JSONEncoder`.
        try JSONEncoder.makeWithDefaults(prettified: false).encode(path: path, fileSystem: fileSystem, self)
    }
}
