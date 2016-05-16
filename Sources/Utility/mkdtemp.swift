/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/**
 Creates a temporary directory for the duration of the provided closure.

 - Note: the contents of the temporary directory is recursively removed.
*/
public func mkdtemp<T>(_ template: String, prefix: String! = nil, body: @noescape(String) throws -> T) throws -> T {

    let dirname = "template.\(NSProcessInfo.processInfo().globallyUniqueString)"

    #if os(OSX)
        let path = NSURL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(dirname, isDirectory: true)
    #else
        let path = NSURL(fileURLWithPath: NSTemporaryDirectory())
            .URLByAppendingPathComponent(dirname, isDirectory: true)!
    #endif

    try NSFileManager.`default`().createDirectory(at: path, withIntermediateDirectories: true, attributes: [:])
    defer { _ = try? NSFileManager.`default`().removeItem(at: path) }

    return try body(path.path!)
}
