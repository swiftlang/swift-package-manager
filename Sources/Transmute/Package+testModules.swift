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
        return walk(path, "Tests", recursively: false).filter{ $0.isDirectory }.flatMap { dir in
            if let sources = try? self.sourcify(dir) {
                return TestModule(basename: dir.basename, sources: sources)
            } else {
                print("warning: no sources in test module: \(path)")
                return nil
            }
        }
    }
}
