/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Get clang's version from the given version output string on Ubuntu.
public func getClangVersion(versionOutput: String) -> (major: Int, minor: Int)? {
    // Clang outputs version in this format on Ubuntu:
    // Ubuntu clang version 3.6.0-2ubuntu1~trusty1 (tags/RELEASE_360/final) (based on LLVM 3.6.0)
    let versionStringPrefix = "Ubuntu clang version "
    let versionStrings = versionOutput.utf8.split(separator: UInt8(ascii: "-")).flatMap(String.init)
    guard let clangVersionString = versionStrings.first,
          clangVersionString.hasPrefix(versionStringPrefix) else {
        return nil
    }
    let versionStartIndex = clangVersionString.index(clangVersionString.startIndex, offsetBy: versionStringPrefix.utf8.count)
    let versionString = clangVersionString[versionStartIndex..<clangVersionString.endIndex]
    // Split major minor patch etc.
    let versions = versionString.utf8.split(separator: UInt8(ascii: ".")).flatMap(String.init)
    guard versions.count > 1, let major = Int(versions[0]), let minor = Int(versions[1]) else {
        return nil
    }
    return (major, minor)
}
