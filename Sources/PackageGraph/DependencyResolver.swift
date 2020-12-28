/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

public enum DependencyResolverError: Error, Equatable {
     /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: PackageIdentity, localPackage: PackageIdentity)
}

public class DependencyResolver {
    public typealias Binding = (container: PackageReference, binding: BoundVersion, products: ProductFilter)
}

extension DependencyResolverError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        }
    }
}
