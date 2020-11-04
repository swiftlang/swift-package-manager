/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel
import PackageLoading
import TSCUtility

/// Write the given tools version at the given path.
///
/// - Parameters:
///   - path: The path of the package.
///   - version: The version to write.
public func writeToolsVersion(at path: AbsolutePath, version: ToolsVersion, fs: FileSystem) throws {
    let file = path.appending(component: Manifest.filename)
    assert(fs.isFile(file), "Tools version file not present")

    /// The current contents of the file.
    let contents = try fs.readFileContents(file)

    let stream = BufferedOutputByteStream()
    // Write out the tools version.
    stream <<< "// swift-tools-version:" <<< Format.asJSON(version.major) <<< "." <<< Format.asJSON(version.minor)
    // Write patch version only if its not zero.
    if version.patch != 0 {
        stream <<< "." <<< Format.asJSON(version.patch)
    }
    stream <<< "\n"
    
    // The following lines up to line 54 append the file contents except for the Swift tools version specification line.
    
    guard let contentsDecodedWithUTF8 = contents.validDescription else {
        throw ToolsVersionLoader.Error.nonUTF8EncodedManifest(path: file)
    }
    
    let manifestComponents = ToolsVersionLoader.split(contentsDecodedWithUTF8)
    
    let toolsVersionSpecificationComponents = manifestComponents.toolsVersionSpecificationComponents
    
    // Replace the Swift tools version specification line if and only if it's well-formed up to the version specifier.
    // This matches the behaviour of the old (now removed) [`ToolsVersionLoader.split(:_)`](https://github.com/WowbaggersLiquidLunch/swift-package-manager/blob/49cfc46bc5defd3ce8e0c0261e3e2cb475bcdb91/Sources/PackageLoading/ToolsVersionLoader.swift#L160).
    if toolsVersionSpecificationComponents.everythingUpToVersionSpecifierIsWellFormed {
        stream <<< ByteString(encodingAsUTF8: String(manifestComponents.contentsAfterToolsVersionSpecification))
    } else {
        stream <<< contents
    }

    try fs.writeFileContents(file, bytes: stream.bytes)
}
