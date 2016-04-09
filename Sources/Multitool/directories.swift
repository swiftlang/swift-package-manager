/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility
import POSIX
import libc

public struct Directories {
    public let root: String
    public let build: String
    public var Packages: String { return Path.join(root, "Packages") }

    private init(root: String) {
        self.root = root
        self.build = getenv("SWIFT_BUILD_PATH") ?? Path.join(root, ".build")
    }
}

public func directories() throws -> Directories {
    return Directories(root: try packageRoot())
}

private func packageRoot() throws -> String {
    var rootd = getcwd()
    while !Path.join(rootd, Manifest.filename).isFile {
        rootd = rootd.parentDirectory
        guard rootd != "/" else {
            throw Error.NoManifestFound
        }
    }
    return rootd
}
