/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/**
 Creates a symbolic link.

 - Note: if relative paths are passed, the current working directory is used for normalization.
*/
public func symlink(create from: String, pointingAt to: String) throws {
    try NSFileManager.`default`().createSymbolicLink(atPath: from, withDestinationPath: to)
}
