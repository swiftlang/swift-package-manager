/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var libc.errno
import func libc.mktemp
import func libc.unlink

#if os(Linux)
    import Foundation  // String.hasSuffix
#endif

/// Creates a temporary file available till duration of closure.
///
/// - Parameters:
///     - template: Filename template to be used.
///     - prefix: If present, this path will be the prefix for file to be created, otherwise
///               temp directory will be used.
///     - body: Closure to be executed. The temp file path will be passed to the closure.
///
/// - Throws: SystemError.mktemp
public func mktemp<T>(_ template: String, prefix: String! = nil, body: @noescape(String) throws -> T) rethrows -> T {
    var prefix = prefix ?? getenv("TMPDIR") ?? "/tmp/"
    if !prefix.hasSuffix("/") { prefix += "/" }

    let path = prefix + "\(template).XXXXXX"

    return try path.withCString { template in
        let mutable = UnsafeMutablePointer<Int8>(template)
        guard let file = libc.mktemp(mutable) else { throw SystemError.mktemp(errno) }
        // Remove the file on exit.
        defer { unlink(file) }
        return try body(String(validatingUTF8: file)!)
    }
}
