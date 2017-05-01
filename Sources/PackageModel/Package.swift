/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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
/// `PackageLoading` target).
///
/// 3. A loaded `PackageModel.Manifest` is an abstract representation of a
/// package, and is used during package dependency resolution. It contains the
/// loaded PackageDescription and information necessary for dependency
/// resolution, but nothing else.
///
/// 4. A loaded `PackageModel.Package` which has had dependencies loaded and
/// resolved. This is the result after `Get.get()`.
///
/// 5. A loaded package, as in #4, for which the targets have also been
/// loaded. There is not currently a data structure for this, but it is the
/// result after `PackageLoading.transmute()`.
public final class Package {
    /// The manifest describing the package.
    public let manifest: Manifest

    /// The local path of the package.
    public let path: AbsolutePath

    /// The name of the package.
    public var name: String {
        return manifest.name
    }

    /// The targets contained in the package.
    public let targets: [Target]

    /// The products produced by the package.
    public let products: [Product]

    // The directory containing the targets which did not explicitly specify
    // their path. If all targets are explicit, this is the preferred path for
    // future targets.
    public let targetSearchPath: AbsolutePath

    // The directory containing the test targets which did not explicitly specify
    // their path. If all test targets are explicit, this is the preferred path
    // for future test targets.
    public let testTargetSearchPath: AbsolutePath

    public init(
        manifest: Manifest,
        path: AbsolutePath,
        targets: [Target],
        products: [Product],
        targetSearchPath: AbsolutePath,
        testTargetSearchPath: AbsolutePath
    ) {
        self.manifest = manifest
        self.path = path
        self.targets = targets
        self.products = products
        self.targetSearchPath = targetSearchPath
        self.testTargetSearchPath = testTargetSearchPath
    }

    public enum Error: Swift.Error {
        case noManifest(baseURL: String, version: String?)
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
    
    public static func == (lhs: Package, rhs: Package) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension Package.Error: Equatable {
    public static func == (lhs: Package.Error, rhs: Package.Error) -> Bool {
        switch (lhs, rhs) {
        case let (.noManifest(lhs), .noManifest(rhs)):
            return lhs.baseURL == rhs.baseURL && lhs.version == rhs.version
        case (.noManifest, _):
            return false
        case let (.noOrigin(lhs), .noOrigin(rhs)):
            return lhs == rhs
        case (.noOrigin, _):
            return false
        }
    }
}
