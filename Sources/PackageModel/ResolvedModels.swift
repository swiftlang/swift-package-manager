/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// Represents a fully resolved module. All the dependencies for the module are resolved.
public final class ResolvedModule: CustomStringConvertible, ObjectIdentifierProtocol {

    /// Represents dependency of a resolved target.
    public enum Dependency {

        /// Direct dependency of the target. This target is in the same package and should be statically linked.
        case target(ResolvedModule)

        /// The target depends on this product.
        case product(ResolvedProduct)
    }

    /// The underlying module represented in this resolved module.
    public let underlyingModule: Module

    /// The name of this module.
    public var name: String {
        return underlyingModule.name
    }

    /// The dependencies of this module.
    public let dependencies: [Dependency]

    /// The transitive closure of the target dependencies. This will also include the
    /// targets which needs to be dynamically linked.
    public lazy var recursiveDependencies: [ResolvedModule] = {
        return try! topologicalSort(self.dependencies, successors: { $0.dependencies }).flatMap({
            guard case .target(let target) = $0 else { return nil }
            return target
        })
    }()

    /// The language-level module name.
    public var c99name: String {
        return underlyingModule.c99name
    }

    /// The "type" of module.
    public var type: Module.Kind {
        return underlyingModule.type
    }

    /// The sources for the module.
    public var sources: Sources {
        return underlyingModule.sources
    }

    /// Create a module instance.
    public init(module: Module, dependencies: [Dependency]) {
        self.underlyingModule = module
        self.dependencies = dependencies
    }

    public var description: String {
        return "<ResolvedModule: \(name)>"
    }
}

/// A fully resolved package. Contains resolved modules, products and dependencies of the package.
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

    /// The modules contained in the package.
    public let modules: [ResolvedModule]

    /// The products produced by the package.
    public let products: [ResolvedProduct]

    /// The dependencies of the package.
    public let dependencies: [ResolvedPackage]

    public init(
        package: Package,
        dependencies: [ResolvedPackage],
        modules: [ResolvedModule],
        products: [ResolvedProduct]
    ) {
        self.underlyingPackage = package
        self.dependencies = dependencies
        self.modules = modules
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

    /// The top level modules contained in this product.
    public let modules: [ResolvedModule]

    /// The type of this product.
    public var type: ProductType {
        return underlyingProduct.type
    }

    /// The outname of this product.
    // FIXME: Should be lifted to build plan.
    public var outname: RelativePath {
        return underlyingProduct.outname
    }

    /// Create an executable module for linux main test manifest file.
    public lazy var linuxMainModule: ResolvedModule = {
        precondition(self.type == .test, "This property is only valid for test product type")
        // FIXME: This is hacky, we should get this from somewhere else.
        let testDirectory = self.modules.first { $0.type == .test }!.sources.root.parentDirectory
        // Path to the main file for test product on linux.
        let linuxMain = testDirectory.appending(component: "LinuxMain.swift")
        // Create an exectutable resolved module with the linux main, adding product's modules as dependencies.
        let swiftModule = SwiftModule(
            linuxMain: linuxMain, name: self.name, dependencies: self.underlyingProduct.modules)

        return ResolvedModule(module: swiftModule, dependencies: self.modules.map(ResolvedModule.Dependency.target))
    }()

    /// The main executable module of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableModule: ResolvedModule {
        precondition(type == .executable, "This property should only be called for executable modules")
        return modules.first {$0.type == .executable}!
    }

    public init(product: Product, modules: [ResolvedModule]) {
        assert(product.modules.count == modules.count && product.modules.map({ $0.name }) == modules.map({ $0.name }))
        self.underlyingProduct = product
        self.modules = modules
    }

    public var description: String {
        return "<ResolvedProduct: \(name)>"
    }
}

extension ResolvedModule.Dependency: Hashable, CustomStringConvertible {

    /// Returns the dependencies of the underlying dependency.
    public var dependencies: [ResolvedModule.Dependency] {
        switch self {
        case .target(let target):
            return target.dependencies
        case .product(let product):
            return product.modules.map(ResolvedModule.Dependency.target)
        }
    }

    // MARK: - Hashable, CustomStringConvertible conformance

    public var hashValue: Int {
        switch self {
            case .product(let p): return p.hashValue
            case .target(let t): return t.hashValue
        }
    }

    public static func == (lhs: ResolvedModule.Dependency, rhs: ResolvedModule.Dependency) -> Bool {
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
        var str = "<ResolvedModule.Dependency: "
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
