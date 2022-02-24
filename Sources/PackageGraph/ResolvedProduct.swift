/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import PackageModel

public final class ResolvedProduct {
    /// The underlying product.
    public let underlyingProduct: Product

    /// The name of this product.
    public var name: String {
        return underlyingProduct.name
    }

    /// The top level targets contained in this product.
    public let targets: [ResolvedTarget]

    /// The type of this product.
    public var type: ProductType {
        return underlyingProduct.type
    }

    /// Executable target for test manifest file.
    public let testManifestTarget: ResolvedTarget?

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public func executableTarget() throws -> ResolvedTarget {
        guard type == .executable || type == .snippet else {
            throw InternalError("firstExecutableModule should only be called for executable targets")
        }
        return targets.first(where: { $0.type == .executable || $0.type == .snippet })!
    }

    public init(product: Product, targets: [ResolvedTarget]) {
        assert(product.targets.count == targets.count && product.targets.map({ $0.name }) == targets.map({ $0.name }))
        self.underlyingProduct = product
        self.targets = targets

        self.testManifestTarget = underlyingProduct.testManifest.map{ testManifest in
            // Create an executable resolved target with the linux main, adding product's targets as dependencies.
            let dependencies: [Target.Dependency] = product.targets.map { .target($0, conditions: []) }
            let swiftTarget = SwiftTarget(testManifest: testManifest, name: product.name, dependencies: dependencies)
            return ResolvedTarget(target: swiftTarget, dependencies: targets.map { .target($0, conditions: []) })
        }
    }

    /// True if this product contains Swift targets.
    public var containsSwiftTargets: Bool {
      //  C targets can't import Swift targets in SwiftPM (at least not right
      // now), so we can just look at the top-level targets.
      //
      // If that ever changes, we'll need to do something more complex here,
      // recursively checking dependencies for SwiftTargets, and considering
      // dynamic library targets to be Swift targets (since the dylib could
      // contain Swift code we don't know about as part of this build).
      return targets.contains { $0.underlyingTarget is SwiftTarget }
    }

    /// Returns the recursive target dependencies.
    public func recursiveTargetDependencies() throws -> [ResolvedTarget] {
        let recursiveDependencies = try targets.lazy.flatMap { try $0.recursiveTargetDependencies() }
        return Array(Set(targets).union(recursiveDependencies))
    }
}

extension ResolvedProduct: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: ResolvedProduct, rhs: ResolvedProduct) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension ResolvedProduct: CustomStringConvertible {
    public var description: String {
        return "<ResolvedProduct: \(name)>"
    }
}
