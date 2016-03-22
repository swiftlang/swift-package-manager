/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

func test(path: String..., testPackageName: String, xctestArg: String? = nil) throws -> Bool {
    let path = Path.join(path)
    var args: [String] = []
    let testsPath: String

#if os(OSX)
    testsPath = Path.join(path, "\(testPackageName).xctest")
    args = ["xcrun", "xctest"]
    if let xctestArg = xctestArg {
        args += ["-XCTest", xctestArg]
    }
#else
    //FIXME: Pass xctestArg when swift-corelibs-xctest supports it
    testsPath = Path.join(path, "test-\(testPackageName)")
#endif

    guard testsPath.testExecutableExists else {
        throw Error.TestsExecutableNotFound
    }

    args += [testsPath]

    let result: Void? = try? system(args)
    return result != nil
}

private extension String {
    var testExecutableExists: Bool {
        #if os(OSX)
            return self.isDirectory //Package.xctest is dir on OSX
        #else
            return self.isFile //test-Package is executable on OSX
        #endif
    }
}
