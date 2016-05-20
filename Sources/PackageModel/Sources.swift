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
    
    static public var validSwiftExtensions = Set<String>(["swift"])
    
    static public var validCExtensions = Set<String>(["c", "m"])

    static public var validCppExtensions = Set<String>(["mm", "cc", "cpp", "cxx"])
        
    static public var validCFamilyExtensions = validCExtensions.union(validCppExtensions)

    static public var validExtensions = { validSwiftExtensions.union(validCExtensions).union(validCFamilyExtensions) }()
}
