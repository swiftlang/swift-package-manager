/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Utility
import class Foundation.NSProcessInfo

func test(path: String, xctestArg: String? = nil) throws -> Bool {

    guard path.isValidTest else {
        throw Error.TestsExecutableNotFound
    }

    var args: [String] = []
#if os(OSX)
    args = ["xcrun", "xctest"]
    if let xctestArg = xctestArg {
        args += ["-XCTest", xctestArg]
    }
    args += [path]
#else
    args += [path]
    if let xctestArg = xctestArg {
        args += [xctestArg]
    }
#endif

    // Execute the XCTest with inherited environment as it is convenient to pass senstive
    // information like username, password etc to test cases via enviornment variables.
    let result: Void? = try? system(args, environment: NSProcessInfo.processInfo().environment)
    return result != nil
}

private extension String {
    var isValidTest: Bool {
        #if os(OSX)
            return isDirectory  // ${foo}.xctest is dir on OSX
        #else
            return isFile       // otherwise ${foo}.xctest is executable file
        #endif
    }
}
