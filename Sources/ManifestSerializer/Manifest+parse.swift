/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageDescription
import PackageModel
import Utility

import func POSIX.realpath
import func POSIX.unlink
import func Utility.fopen

extension Manifest {
    /// Create a manifest by loading from the given path.
    ///
    /// - path: The path to the manifest file or directory containing `Package.swift`.
    public init(path inputPath: String, baseURL: String, swiftc: String, libdir: String) throws {
        guard baseURL.chuzzle() != nil else { fatalError() }  //TODO

        // Canonicalize the URL.
        var baseURL = baseURL
        if URL.scheme(baseURL) == nil {
            baseURL = try realpath(baseURL)
        }

        // Compute the actual input file path.
        let path: String = inputPath.isDirectory ? Path.join(inputPath, Manifest.filename) : inputPath

        // Validate that the file exists.
        guard path.isFile else { throw PackageModel.Package.Error.NoManifest(path) }

        // Load the manifest description.
        if let toml = try parse(path: path, swiftc: swiftc, libdir: libdir) {
            let toml = try TOMLItem.parse(toml)
            let package = PackageDescription.Package.fromTOML(toml, baseURL: baseURL)
            let products = PackageDescription.Product.fromTOML(toml)

            self.init(path: path, package: package, products: products)
        } else {
            // As a special case, we accept an empty file as an unnamed package.
            //
            // FIXME: We should deprecate this, now that we have the `init` functionality.
            self.init(path: path, package: PackageDescription.Package(), products: [])
        }
    }
}

private func parse(path manifestPath: String, swiftc: String, libdir: String) throws -> String? {
    // For now, we load the manifest by having Swift interpret it directly.
    // Eventually, we should have two loading processes, one that loads only the
    // the declarative package specification using the Swift compiler directly
    // and validates it.

    var cmd = [swiftc]
    cmd += ["--driver-mode=swift"]
    cmd += verbosity.ccArgs
    cmd += ["-I", libdir]
    cmd += ["-L", libdir, "-lPackageDescription"]
#if os(OSX)
    cmd += ["-target", "x86_64-apple-macosx10.10"]
#endif
    cmd += [manifestPath]

    //Create and open a temporary file to write toml to
    let filePath = Path.join(manifestPath.parentDirectory, ".Package.toml")
    let fp = try fopen(filePath, mode: .Write)
    defer { fp.closeFile() }

    //Pass the fd in arguments
    cmd += ["-fileno", "\(fp.fileDescriptor)"]
    try system(cmd)

    let toml = try fopen(filePath).reduce("") { $0 + "\n" + $1 }
    try unlink(filePath) //Delete the temp file after reading it

    return toml != "" ? toml : nil
}
