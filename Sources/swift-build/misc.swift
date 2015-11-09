/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getcwd
import struct sys.Path
import struct dep.Manifest

enum Error: ErrorType {
    case NoManifestFound
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .NoManifestFound:
            return "No \(Manifest.filename) file found"
        }
    }
}

func findSourceRoot() throws -> String {
    var rootd = try getcwd()
    while !Path.join(rootd, Manifest.filename).isFile {
        rootd = rootd.parentDirectory
        guard rootd != "/" else {
            throw Error.NoManifestFound
        }
    }
    return rootd
}
