/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import PackageModel
import SourceControl

extension Manifest.RawPackage {

    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints() -> [RepositoryPackageConstraint] {
        return dependencies.map {
            let requirement: RepositoryPackageConstraint.Requirement

            switch $0.requirement {
            case .range(let range):
                requirement = .versionSet(.range(range.asUtilityVersion))

            case .revision(let identifier):
                assert(identifier.characters.count == 40)
                assert(Git.checkRefFormat(ref: identifier))

                requirement = .revision(identifier)

            case .branch(let identifier):
                assert(Git.checkRefFormat(ref: identifier))

                requirement = .revision(identifier)
            }

            return RepositoryPackageConstraint(
                container: RepositorySpecifier(url: $0.url), requirement: requirement)
        }
    }
}
