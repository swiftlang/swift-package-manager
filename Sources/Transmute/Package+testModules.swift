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
    func testModules() throws -> [TestModule] {
        let testsPath = Path.join(path, "Tests")
        //Don't try to walk Tests if it is in excludes
        if testsPath.isDirectory && excludes.contains(testsPath) { return [] }
        return try walk(testsPath, recursively: false).filter(shouldConsiderDirectory).flatMap { dir in
            let sources = walk(dir, recursing: shouldConsiderDirectory).filter{ isValidSource($0, validExtensions: Sources.validSwiftExtensions) }
            if sources.count > 0 {
                return try TestModule(basename: dir.basename, sources: Sources(paths: sources, root: dir))
            } else {
                print("warning: no sources in test module: \(path)")
                return nil
            }
        }
    }
}
