//
//  PrebuiltLibrary.swift
//  SwiftPM
//
//  Created by Doug Schaefer on 2025-10-16.
//

import Basics

/// A structure representing a prebuilt library to be used instead of a source dependency
public struct PrebuiltLibrary {
    /// The package identity.
    public let identity: PackageIdentity

    /// The name of the binary target the artifact corresponds to.
    public let libraryName: String

    /// The path to the extracted prebuilt artifacts
    public let path: AbsolutePath

    /// The path to the checked out source
    public let checkoutPath: AbsolutePath?

    /// The products in the library
    public let products: [String]

    /// The include path relative to the checkouts dir
    public let includePath: [RelativePath]?

    /// The C modules that need their includes directory added to the include path
    public let cModules: [String]

    public init(
        identity: PackageIdentity,
        libraryName: String,
        path: AbsolutePath,
        checkoutPath: AbsolutePath?,
        products: [String],
        includePath: [RelativePath]? = nil,
        cModules: [String] = []
    ) {
        self.identity = identity
        self.libraryName = libraryName
        self.path = path
        self.checkoutPath = checkoutPath
        self.products = products
        self.includePath = includePath
        self.cModules = cModules
    }
}

