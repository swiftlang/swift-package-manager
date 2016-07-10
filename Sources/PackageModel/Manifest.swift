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
    public let path: String
    public let package: PackageDescription.Package
    public let products: [PackageDescription.Product]


    public init(path: String, package: PackageDescription.Package, products: [PackageDescription.Product]) {
        self.path = path
        self.package = package
        self.products = products
    }

    // this is here because we need a strictly narrow module for constants
    // when we lose libc because Swift proper gets a CPOSIX then we can
    // rename this module to Constants

    public static var filename: String { return "Package.swift" }
}
