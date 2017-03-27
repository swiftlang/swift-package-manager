/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel

/// Represents the inputs to the package graph.
public struct PackageGraphRoot {

    /// Represents a top level package dependencies.
    public struct PackageDependency {

        // Location of this dependency.
        //
        // Opaque location object which will be included in any diagnostics
        // related to this dependency.  Clients can use this identify where this
        // dependency is declared.
        public let location: String

        /// The URL of the package.
        public let url: String

        /// The requirement of the package.
        public let requirement: RepositoryPackageConstraint.Requirement

        public init(
            url: String,
            requirement: RepositoryPackageConstraint.Requirement,
            location: String
        ) {
            self.url = url
            self.requirement = requirement 
            self.location = location
        }
    }
    
    /// The list of root manifests.
    public let manifests: [Manifest]

    /// The top level dependencies.
    public let dependencies: [PackageDependency]

    /// Create a package graph root.
    public init(manifests: [Manifest], dependencies: [PackageDependency] = []) {
        self.manifests = manifests
        self.dependencies = dependencies
    }
}
