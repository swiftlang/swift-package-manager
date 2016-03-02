/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

public struct TestModule {
    struct Class {
        let name: String
        let testMethods: [String]
    }
    let name: String
    let classes: [Class]
}

public func parseAST(dir: String) throws -> [TestModule] {
    var testModules: [TestModule] = []

    try walk(dir, recursively: false).filter{$0.isFile}.forEach { file in
        let fp = File(path: file)
        let astString = try fp.enumerate().reduce("") { $0 + $1 }
        let fileName = file.basename
        let moduleName = fileName[fileName.startIndex..<fileName.endIndex.advancedBy(-4)]
        print("Processing \(moduleName) AST")
        testModules += [parseASTString(astString, module: moduleName)]
    }
    
    return testModules
}
