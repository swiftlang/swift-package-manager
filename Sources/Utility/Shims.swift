/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------

 Platform-specific shims for the Swift3 transition.
*/

#if os(OSX)

import Foundation

public typealias NSFileHandle = FileHandle
public typealias NSFileManager = FileManager
public typealias NSJSONSerialization = JSONSerialization
public typealias NSProcessInfo = ProcessInfo

public let NSUTF8StringEncoding = String.Encoding.utf8

extension NSJSONSerialization {
    public static func jsonObject(with data: NSData, options: JSONSerialization.ReadingOptions) throws -> AnyObject {
        return try JSONSerialization.jsonObject(with: data as Data, options: options)
    }
}

extension NSFileHandle {
    public func write(_ data: NSData) {
        write(data as Data)
    }
}

#endif
