/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import func POSIX.getenv
import func POSIX.getcwd

private let PATH = [POSIX.getcwd()] + (getenv("PATH") ?? "").components(separatedBy: ":")

private var memo = [String: String]()

/**
 Resolves the command to the absolute path by looking up
 CWD and PATH.
 */
public func which(_ arg0: String) throws -> String {
    if arg0.isAbsolute {
        return arg0
    }
    if let path = memo[arg0] {
        return path
    }
    for prefix in PATH {
        let path = Path.join([prefix, arg0])
        if path.isFile {
            memo[arg0] = path
            return path
        }
    }
    throw Error.UnknownCommand(arg0: arg0)
}
