/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

private var memoized = [String: String]()

public func which(_ arg0: String) -> String {
    if arg0.isAbsolute {
        return arg0
    } else if let fullpath = memoized[arg0] {
        return fullpath
    } else if let fullpath = try? Utility.popen(["/bin/sh", "-c", "which \(arg0)"]) {
        memoized[arg0] = fullpath.chomp()
        return fullpath.chomp()
    } else {
        return arg0
    }
}

