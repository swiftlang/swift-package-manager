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

public func directories() throws -> (root: String, build: String) {
    let pkg = try packageRoot()
    let bld = getenv("SWIFT_BUILD_PATH") ?? Path.join(pkg, ".build")
    return (pkg, bld)
}

private func packageRoot() throws -> String {
    var rootd = try getcwd()
    while !Path.join(rootd, Manifest.filename).isFile {
        rootd = rootd.parentDirectory
        guard rootd != "/" else {
            throw Error.NoManifestFound
        }
    }
    return rootd
}
