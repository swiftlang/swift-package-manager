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
        return try walk(path, "Tests", recursively: false).filter{ $0.isDirectory }.map { dir in
            return TestModule(basename: dir.basename, sources: try self.sourcify(dir))
        }
    }
}
