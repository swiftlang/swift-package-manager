/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Create a directory at the given path, recursively.
///
/// It is *not* an error if the directory already exists.
///
/// - param path: The path to create, which must be absolute.
public func makeDirectories(_ path: String) throws {
    precondition(path.hasPrefix("/"), "unexpected relative path")
  #if os(Linux)
    try FileManager.default().createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [:])
  #else
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [:])
  #endif
}
