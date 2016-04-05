/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import PackageType
import Utility

public func build(YAMLPath: String, target: String) throws {
    var args = [llbuild, "-f", YAMLPath, target]
    if verbosity != .Concise { args.append("-v") }
    try system(args)
}
