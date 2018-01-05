/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// Represents a fully resolved target. All the dependencies for the target are resolved.
public final class ResolvedTarget: CustomStringConvertible, ObjectIdentifierProtocol {

    /// Represents dependency of a resolved target.
    public enum Dependency {

        /// Direct dependency of the target. This target is in the same package and should be statically linked.
        case target(ResolvedTarget)

        /// The target depends on this product.
        case product(ResolvedProduct)
    }

    /// The underlying target represented in this resolved target.
    public let underlyingTarget: Target

    /// The name of this target.
    public var name: String {
        return underlyingTarget.name
    }

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The transitive closure of the target dependencies. This will also include the
    /// targets which needs to be dynamically linked.
    public lazy var recursiveDependencies: [ResolvedTarget] = {
        return try! topologicalSort(self.dependencies, successors: { $0.dependencies }).flatMap({
            guard case .target(let target) = $0 else { return nil }
            return target
        })
    }()

    /// The language-level target name.
    public var c99name: String {
        return underlyingTarget.c99name
    }

    /// The "type" of target.
    public var type: Target.Kind {
        return underlyingTarget.type
    }

    /// The sources for the target.
    public var sources: Sources {
        return underlyingTarget.sources
    }

    /// Create a target instance.
    public init(target: Target, dependencies: [Dependency]) {
        self.underlyingTarget = target
        self.dependencies = dependencies
    }

    public var description: String {
        return "<ResolvedTarget: \(name)>"
    }
}

/// A fully resolved package. Contains resolved targets, products and dependencies of the package.
public final class ResolvedPackage: CustomStringConvertible, ObjectIdentifierProtocol {

    /// The underlying package reference.
    public let underlyingPackage: Package

    /// The manifest describing the package.
    public var manifest: Manifest {
        return underlyingPackage.manifest
    }

    /// The name of the package.
    public var name: String {
        return underlyingPackage.name
    }

    /// The local path of the package.
    public var path: AbsolutePath {
        return underlyingPackage.path
    }

    /// The targets contained in the package.
    public let targets: [ResolvedTarget]

    /// The products produced by the package.
    public let products: [ResolvedProduct]

    /// The dependencies of the package.
    public let dependencies: [ResolvedPackage]

    public init(
        package: Package,
        dependencies: [ResolvedPackage],
        targets: [ResolvedTarget],
        products: [ResolvedProduct]
    ) {
        self.underlyingPackage = package
        self.dependencies = dependencies
        self.targets = targets
        self.products = products
    }

    public var description: String {
        return "<ResolvedPackage: \(name)>"
    }
}

public final class ResolvedProduct: ObjectIdentifierProtocol, CustomStringConvertible {

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

    /// Executable target for linux main test manifest file.
    public let linuxMainTarget: ResolvedTarget?

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableModule: ResolvedTarget {
        precondition(type == .executable, "This property should only be called for executable targets")
        return targets.first(where: { $0.type == .executable })!
    }

    public init(product: Product, targets: [ResolvedTarget]) {
        assert(product.targets.count == targets.count && product.targets.map({ $0.name }) == targets.map({ $0.name }))
        self.underlyingProduct = product
        self.targets = targets

        self.linuxMainTarget = underlyingProduct.linuxMain.map({ linuxMain in
            // Create an exectutable resolved target with the linux main, adding product's targets as dependencies.
            let swiftTarget = SwiftTarget(
                linuxMain: linuxMain, name: product.name, dependencies: product.targets)
            return ResolvedTarget(target: swiftTarget, dependencies: targets.map(ResolvedTarget.Dependency.target))
        })
    }

    public var description: String {
        return "<ResolvedProduct: \(name)>"
    }
}

extension ResolvedTarget.Dependency: Hashable, CustomStringConvertible {

    /// Returns the dependencies of the underlying dependency.
    public var dependencies: [ResolvedTarget.Dependency] {
        switch self {
        case .target(let target):
            return target.dependencies
        case .product(let product):
            return product.targets.map(ResolvedTarget.Dependency.target)
        }
    }

    // MARK: - Hashable, CustomStringConvertible conformance

    public var hashValue: Int {
        switch self {
            case .product(let p): return p.hashValue
            case .target(let t): return t.hashValue
        }
    }

    public static func == (lhs: ResolvedTarget.Dependency, rhs: ResolvedTarget.Dependency) -> Bool {
        switch (lhs, rhs) {
        case (.product(let l), .product(let r)):
            return l == r
        case (.product, _):
            return false
        case (.target(let l), .target(let r)):
            return l == r
        case (.target, _):
            return false
        }
    }

    public var description: String {
        var str = "<ResolvedTarget.Dependency: "
        switch self {
        case .product(let p):
            str += p.description
        case .target(let t):
            str += t.description
        }
        str += ">"
        return str
    }
}
