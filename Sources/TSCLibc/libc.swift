/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(Glibc)
@_exported import Glibc
#elseif os(Windows)
@_exported import MSVCRT
@_exported import WinSDK
#else
@_exported import Darwin.C
#endif

@_exported import TSCclibc

#if os(Windows)
// char *realpath(const char *path, char *resolved_path);
public func realpath(
    _ path: String,
    _ resolvedPath: UnsafeMiutableBufferPointer<CChar>?
) -> UnsafePointer<CChar>? {
  fatalError("realpath is unimplemented")
}
#endif
