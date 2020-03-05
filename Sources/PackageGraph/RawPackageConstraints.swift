/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import SourceControl

extension PackageDependencyDescription {
    /// Create the package reference object for the dependency.
    public func createPackageRef(config: SwiftPMConfig) -> PackageReference {
        let effectiveURL = config.mirroredURL(forURL: self.url)
        return PackageReference(
            identity: PackageReference.computeIdentity(packageURL: effectiveURL),
            path: effectiveURL,
            kind: requirement == .localPackage ? .local : .remote
        )
    }
}

extension Manifest {

    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints(config: SwiftPMConfig) -> [RepositoryPackageConstraint] {
        return allRequiredDependencies.map({
            return RepositoryPackageConstraint(
                container: $0.createPackageRef(config: config),
                requirement: $0.requirement.toConstraintRequirement())
        })
    }
}
