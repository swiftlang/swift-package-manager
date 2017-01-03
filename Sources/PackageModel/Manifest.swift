/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageDescription

/**
 This contains the declarative specification loaded from package manifest
 files, and the tools for working with the manifest.
*/
public struct Manifest {
    /// The standard filename for the manifest.
    public static var filename = basename + ".swift"

    /// The standard basename for the manifest.
    public static var basename = "Package"

    /// The path of the manifest file.
    //
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    public let path: AbsolutePath

    /// The repository URL the manifest was loaded from.
    //
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    public let url: String

    /// The raw package description.
    public let package: PackageDescription.Package

    /// The version this package was loaded from, if known.
    public let version: Version?

    /// The name of the package.
    public var name: String {
        return package.name
    }

    public init(path: AbsolutePath, url: String, package: PackageDescription.Package, version: Version?) {
        self.path = path
        self.url = url
        self.package = package
        self.version = version
    }
}

extension Manifest {
    /// Returns JSON representation of this manifest.
    // Note: Right now we just return the JSON representation of the package,
    // but this can be expanded to include the details about manifest too.
    public func jsonString() throws -> String {
        // FIXME: It is unfortunate to re-parse the JSON string.
        return try JSON(string: PackageDescription.jsonString(package: package)).toString(prettyPrint: true)
    }
}

extension Manifest: Hashable {

    public static func ==(lhs: Manifest, rhs: Manifest) -> Bool {
        // FIXME: Maybe we should make PackageDescription.Package conform to Equatable.
        return lhs.name == rhs.name &&
               lhs.package === rhs.package
    }

    public var hashValue: Int {
        return name.hashValue
    }
}
