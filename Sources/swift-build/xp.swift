/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility
import Build
import POSIX

#if os(Linux)
public func describe(prefix: String, _ conf: Configuration, _ modules: [Module], _ products: [Product], Xcc: [String], Xld: [String], Xswiftc: [String]) throws -> String {
    do {
        return try Build.describe(prefix, conf, modules, products, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)
    } catch {

        if (try? Utility.popen(["command", "-v", "clang++"])) == nil {
            print("warning: clang++ not found: this will cause build failure", toStream: &stderr)
        }

        throw error
    }
}
#endif
