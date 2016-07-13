/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines the support for loading the Swift-based manifest files.
*/

import PackageDescription

/**
 This contains the declarative specification loaded from package manifest
 files, and the tools for working with the manifest.
*/
public struct Manifest {
    /// The standard filename for the manifest.
    public static var filename = "Package.swift"

    /// The path of the manifest file.
    //
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    public let path: String

    /// The raw package description.
    public let package: PackageDescription.Package

    /// The raw product descriptions.
    public let products: [PackageDescription.Product]

    /// The version this package was loaded from, if known.
    public let version: Version?

    public init(path: String, package: PackageDescription.Package, products: [PackageDescription.Product], version: Version?) {
        self.path = path
        self.package = package
        self.products = products
        self.version = version
    }
}
