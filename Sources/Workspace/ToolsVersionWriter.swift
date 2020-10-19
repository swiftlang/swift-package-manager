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
	// FIXME: `split(_:)` above has been deprecated.
	// However, its replacement (commented out below) causes failures in `FunctionTests` and `WorkspaceTests`.
//	guard let contentsDecodedWithUTF8 = contents.validDescription else {
//		throw ToolsVersionLoader.Error.nonUTF8EncodedManifest(path: file)
//	}
//	// It's safe to force-unwrap, because `contentsDecodedWithUTF8` has been successfully decoded using UTF-8.
//	stream <<< ToolsVersionLoader.split(contentsDecodedWithUTF8).contentsAfterToolsVersionSpecification.data(using: .utf8)!

    try fs.writeFileContents(file, bytes: stream.bytes)
}
