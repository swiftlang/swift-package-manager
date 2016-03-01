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
        let (directories, files) = walk(path, "Tests", recursively: false).partition{ $0.isDirectory }

        let testDirectories = directories.filter{ !excludes.contains($0) }
        let rootTestFiles = files.filter { 
            !$0.hasSuffix("LinuxMain.swift") && isValidSource($0) && !excludes.contains($0)
        }

        if (testDirectories.count > 0 && rootTestFiles.count > 0) {
            throw ModuleError.InvalidLayout(.InvalidLayout)            
        } else if (testDirectories.count > 0) {
            return try testDirectories.map { 
                TestModule(basename: $0.basename, sources: try self.sourcify($0)) 
            }
        } else {
            if (rootTestFiles.count > 0) {
                let rootTestSource = Sources(paths: rootTestFiles, root: path)
                return [TestModule(basename: name, sources: rootTestSource)]
            }
        }
        
        return []
    }
}
