/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

extension Package {
    public func sourceRoot() throws -> String {

        let viableRoots = walk(path, recursively: false).filter { entry in
            switch entry.basename.lowercased() {
            case "sources", "source", "src", "srcs":
                return entry.isDirectory && !manifest.package.exclude.contains(entry)
            default:
                return false
            }
        }

        switch viableRoots.count {
        case 0:
            return path.normpath
        case 1:
            return viableRoots[0]
        default:
            // eg. there is a `Sources' AND a `src'
            throw ModuleError.InvalidLayout(.MultipleSourceRoots(viableRoots))
        }
    }
}
