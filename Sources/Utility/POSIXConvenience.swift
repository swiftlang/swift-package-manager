/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX

public func fopen(_ path: String..., mode: FopenMode = .Read, body: (UnsafeMutablePointer<FILE>) throws -> Void) throws {
    var fp = try POSIX.fopen(Path.join(path), mode: mode)
    defer { if fp != nil { fclose(fp) } }
    try body(fp)
    fclose(fp)  // defer is not necessarily immediate
    fp = nil
}

@_exported import func POSIX.fputs

@_exported import typealias libc.FILE
@_exported import func libc.fclose
@_exported import func libc.fwrite
