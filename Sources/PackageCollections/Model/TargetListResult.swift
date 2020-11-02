/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

import SourceControl
import TSCUtility

extension PackageCollectionsModel {
    /// Target metadata
    public typealias TargetListResult = [TargetListItem]

    public struct TargetListItem {
        /// Target
        public let target: PackageCollectionsModel.PackageTarget

        /// Packages where the target is found
        public let packages: [Package]
    }
}

extension PackageCollectionsModel.TargetListResult {
    /// Metadata of package that contains the target
    public struct Package {
        public typealias Version = PackageVersion

        /// Package's repository address
        public let repository: RepositorySpecifier

        /// Package description
        public let description: String?

        /// Package versions that contain the target
        public let versions: [Version]

        /// Package collections that contain this package and at least one of the `versions`
        public let collections: [PackageCollectionsModel.PackageCollectionIdentifier]
    }
}

extension PackageCollectionsModel.TargetListResult {
    /// Represents a package version
    public struct PackageVersion {
        /// The version
        public let version: TSCUtility.Version

        /// Package name
        public let packageName: String
    }
}
