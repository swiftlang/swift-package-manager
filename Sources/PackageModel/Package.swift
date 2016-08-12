/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

// Re-export Version from PackageModel, since it is a key part of the model.
@_exported import struct Utility.Version

/// The basic package representation.
///
/// The package manager conceptually works with five different kinds of
/// packages, of which this is only one:
///
/// 1. Informally, the repository containing a package can be thought of in some
/// sense as the "package". However, this isn't accurate, because the actual
/// Package is derived from its manifest, a Package only actually exists at a
/// particular repository revision (typically a tag). We also may eventually
/// want to support multiple packages within a single repository.
///
/// 2. The `PackageDescription.Package` as defined inside a manifest is a
/// declarative specification for (part of) the package but not the object that
/// the package manager itself is typically working with internally. Rather,
/// that specification is primarily used to load the package (see the
/// `PackageLoading` module).
///
/// 3. A loaded `PackageModel.Manifest` is an abstract representation of a
/// package, and is used during package dependency resolution. It contains the
/// loaded PackageDescription and information necessary for dependency
/// resolution, but nothing else.
///
/// 4. A loaded `PackageModel.Package` which has had dependencies loaded and
/// resolved. This is the result after `Get.get()`.
///
/// 5. A loaded package, as in #4, for which the modules have also been
/// loaded. There is not currently a data structure for this, but it is the
/// result after `PackageLoading.transmute()`.
public final class Package {
    /// The manifest describing the package.
    public let manifest: Manifest
    
    /// The local path of the package.
    public let path: AbsolutePath

    /// The name of the package.
    public var name: String {
        return manifest.package.name
    }        
    
    /// The URL the package was loaded from.
    //
    // FIXME: This probably doesn't belong here...
    //
    // FIXME: Eliminate this method forward.
    public var url: String {
        return manifest.url
    }

    /// The version this package was loaded from, if known.
    //
    // FIXME: Eliminate this method forward.
    public var version: Version? {
        return manifest.version
    }

    /// The modules contained in the package.
    public let modules: [Module]

    /// The test modules contained in the package.
    //
    // FIXME: Should these just be merged with the regular modules?
    public let testModules: [Module]

    /// The products produced by the package.
    public let products: [Product]

    /// The resolved dependencies of the package.
    ///
    /// This value is only available once package loading is complete.
    public var dependencies: [Package] = []

    public init(manifest: Manifest, path: AbsolutePath, modules: [Module], testModules: [Module], products: [Product]) {
        self.manifest = manifest
        self.path = path
        self.modules = modules
        self.testModules = testModules
        self.products = products
    }

    public enum Error: Swift.Error, Equatable {
        case noManifest(String)
        case noOrigin(String)
    }
}

extension Package: CustomStringConvertible {
    public var description: String {
        return name
    }
}

extension Package: Hashable, Equatable {
    public var hashValue: Int { return ObjectIdentifier(self).hashValue }
}

public func ==(lhs: Package, rhs: Package) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

public func ==(lhs: Package.Error, rhs: Package.Error) -> Bool {
    switch (lhs, rhs) {
    case let (.noManifest(lhs), .noManifest(rhs)):
        return lhs == rhs
    case (.noManifest, _):
        return false
    case let (.noOrigin(lhs), .noOrigin(rhs)):
        return lhs == rhs
    case (.noOrigin, _):
        return false
    }
}
