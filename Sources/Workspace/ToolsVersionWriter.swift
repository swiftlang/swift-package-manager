/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import PackageLoading
import Utility

/// Write the given tools version at the given path.
///
/// - Parameters:
///   - path: The path of the package.
///   - version: The version to write.
public func writeToolsVersion(at path: AbsolutePath, version: ToolsVersion, fs: inout FileSystem) throws {
    let file = path.appending(component: Manifest.filename)
    assert(fs.isFile(file), "Tools version file not present")

    // Get the current contents of the file.
    let contents = try fs.readFileContents(file)

    let stream = BufferedOutputByteStream()
    // Write out the tools version.
    stream <<< "// swift-tools-version:" <<< Format.asJSON(version.major) <<< "." <<< Format.asJSON(version.minor)
    // Write patch version only if its not zero.
    if version.patch != 0 {
        stream <<< "." <<< Format.asJSON(version.patch)
    }
    stream <<< "\n"
    // Append the file contents except for version specifier line.
    stream <<< ToolsVersionLoader.split(contents).rest

    try fs.writeFileContents(file, bytes: stream.bytes)
}

public extension ToolsVersion {

    /// Returns the tools version with zeroed patch number.
    public var zeroedPatch: ToolsVersion {
        return ToolsVersion(version: Version(major, minor, 0))
    }
}
