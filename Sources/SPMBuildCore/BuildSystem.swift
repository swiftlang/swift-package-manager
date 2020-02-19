/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageGraph

/// An enum representing what subset of the package to build.
public enum BuildSubset {
    /// Represents the subset of all products and non-test targets.
    case allExcludingTests

    /// Represents the subset of all products and targets.
    case allIncludingTests

    /// Represents a specific product.
    case product(String)

    /// Represents a specific target.
    case target(String)
}

/// A protocol that represents a build system used by SwiftPM for all build operations. This allows factoring out the
/// implementation details between SwiftPM's `BuildOperation` and the XCBuild backed `XCBuildSystem`.
public protocol BuildSystem {

    /// The test products that this build system will build.
    var builtTestProducts: [BuiltTestProduct] { get }

    /// Returns the package graph used by the build system.
    func getPackageGraph() throws -> PackageGraph

    /// Builds a subset of the package graph.
    /// - Parameters:
    ///   - subset: The subset of the package graph to build.
    func build(subset: BuildSubset) throws

    /// Cancels the currently running operation, if possible.
    func cancel()
}

extension BuildSystem {

    /// Builds the default subset: all targets excluding tests.
    public func build() throws {
        try build(subset: .allExcludingTests)
    }
}
