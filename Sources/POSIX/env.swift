/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func SPMLibc.setenv
import func SPMLibc.unsetenv
import var SPMLibc.errno

public func setenv(_ key: String, value: String) throws {
    guard SPMLibc.setenv(key, value, 1) == 0 else {
        throw SystemError.setenv(errno, key)
    }
}

public func unsetenv(_ key: String) throws {
    guard SPMLibc.unsetenv(key) == 0 else {
        throw SystemError.unsetenv(errno, key)
    }
}
