/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

public struct Sources {
    public let relativePaths: [String]
    public let root: String

    public var paths: [String] {
        for relativePath in relativePaths {
            assert(!relativePath.hasPrefix("/"))
        }

        return relativePaths.map{ Path.join(root, $0) }
    }

    public init(paths: [String], root: String) {
        relativePaths = paths.map { Path($0).relative(to: root) }
        self.root = root
    }
    
    static public var validSwiftExtensions: Set<String> {
        return ["swift"]
    }
    
    static public var validCExtensions: Set<String> {
        return ["c"]
    }
    
    static public var validExtensions: Set<String> {
        return validSwiftExtensions.union(validCExtensions)
    }
}
