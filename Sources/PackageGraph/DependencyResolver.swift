/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

public enum DependencyResolverError: Error, Equatable, CustomStringConvertible {
     /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: String, localPackage: String)

    public static func == (lhs: DependencyResolverError, rhs: DependencyResolverError) -> Bool {
        switch (lhs, rhs) {
        case (.revisionDependencyContainsLocalPackage(let a1, let b1), .revisionDependencyContainsLocalPackage(let a2, let b2)):
            return a1 == a2 && b1 == b2
        }
    }

    public var description: String {
        switch self {
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        }
    }
}

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
}

public class DependencyResolver {
    public typealias Binding = (container: PackageReference, binding: BoundVersion, products: ProductFilter)

    /// The dependency resolver result.
    public enum Result {
        /// A valid and complete assignment was found.
        case success([Binding])

        /// The resolver encountered an error during resolution.
        case error(Swift.Error)
    }
}
