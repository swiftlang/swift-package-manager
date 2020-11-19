// Workspace/ToolsVersionWriter.swift - Prepends/replaces Swift tools version specifications in manifest files.
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file implements global functions that prepend any given manifest file with a Swift tools version specification.
///
// -----------------------------------------------------------------------------

import TSCBasic
import PackageModel
import PackageLoading
import TSCUtility

/// Prepends a Swift tools version specification to the non-version-specific manifest file (`Package.swift`) in the given directory.
///
/// If the main manifest file already contains a valid tools version specification (ignoring the validity of the version specifier and that of everything following it), then the existing specification is replaced by this new one.
///
/// The version specifier in the specification does not contain any build metadata or pre-release identifier. The patch version is included if and only if it's not zero.
///
/// A `FileSystemError` is thrown if the manifest file is unable to be read from or written to.
///
/// - Precondition: `manifestDirectoryPath` must be a valid path to a directory that contains a `Package.swift` file.
///
/// - Parameters:
///   - manifestDirectoryPath: The absolute path to the given directory.
///   - toolsVersion: The Swift tools version to specify as the lowest supported version.
///   - fileSystem: The filesystem to read/write the manifest file on.
///
/// - Throws: A `FileSystemError` instance, if the manifest file is unable to be located, read from, or written to..
public func prependToolsVersionSpecification(toDefaultManifestIn manifestDirectoryPath: AbsolutePath, specifying toolsVersion: ToolsVersion, fileSystem: FileSystem) throws {
    let manifestFilePath = manifestDirectoryPath.appending(component: Manifest.filename)
    try prependToolsVersionSpecification(toManifestAt: manifestFilePath, specifying: toolsVersion, fileSystem: fileSystem)
}

// FIXME: Throw an error if the specified version is greater than the version-specific manifest's version?
// For example, if the manifest file is Package@swift-4.0.swift and the given version to specify is 5.0.
/// Prepends a Swift tools version specification to the specified manifest file.
///
/// If the main manifest file already contains a valid tools version specification (ignoring the validity of the version specifier and that of everything following it), then the existing specification is replaced by this new one.
///
/// The version specifier in the specification does not contain any build metadata or pre-release identifier. The patch version is included if and only if it's not zero.
///
/// A `FileSystemError` is thrown if the manifest file is unable to be located, read from, or written to.
///
/// - Precondition: `manifestFilePath` must be a valid path to a file.
///
/// - Parameters:
///   - manifestFilePath: The absolute path to the specified manifest file.
///   - toolsVersion: The Swift tools version to specify as the lowest supported version.
///   - fileSystem: The filesystem to read/write the manifest file on.
///
/// - Throws: A `FileSystemError` instance, if the manifest file is unable to be read from or written to..
public func prependToolsVersionSpecification(toManifestAt manifestFilePath: AbsolutePath, specifying toolsVersion: ToolsVersion, fileSystem: FileSystem) throws {
    // FIXME: Throw a `FileSystemError` instead?
    // The only problem is that there doesn't seem to be a `FileSystemError.Kind` case that describes this kind of error.
    // Or, we can revert it back to an assert, and let `fileSystem.readFileContents(manifestFilePath)` throw an error if the file can't be found.
    precondition(fileSystem.isFile(manifestFilePath), "cannot locate the manifest file at \(manifestFilePath)")
    /// The current contents of the file.
    let contents = try fileSystem.readFileContents(manifestFilePath)
    
    let stream = BufferedOutputByteStream()
    // Write out the tools version.
    stream <<< "// swift-tools-version:\(toolsVersion.major).\(toolsVersion.minor)"
    // Write patch version only if it's not zero.
    if toolsVersion.patch != 0 {
        stream <<< ".\(toolsVersion.patch)"
    }
    stream <<< "\n"
    
    // The following lines up to line 77 append the file contents except for the Swift tools version specification line.
    
    guard let contentsDecodedWithUTF8 = contents.validDescription else {
        throw ToolsVersionLoader.Error.nonUTF8EncodedManifest(path: manifestFilePath)
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
    
    try fileSystem.writeFileContents(manifestFilePath, bytes: stream.bytes)
}
