/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import PackageDescription4
import SourceControl

extension PackageDescription4.Package.Dependency {
    /// Create the package reference object for the dependency.
    public func createPackageRef() -> PackageReference {
        return PackageReference(
            identity: PackageReference.computeIdentity(packageURL: url),
            path: url
        )
    }
}

extension Manifest.RawPackage {

    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints() -> [RepositoryPackageConstraint] {
        return dependencies.map({
            return RepositoryPackageConstraint(
                container: $0.createPackageRef(),
                requirement: $0.requirement.toConstraintRequirement())
        })
    }
}
