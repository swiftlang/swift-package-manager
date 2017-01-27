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

    /// The underlying module represented in this resolved module.
    public let underlyingModule: Module

    /// The name of this module.
    public var name: String {
        return underlyingModule.name
    }

    /// The direct dependencies of this module.
    public let dependencies: [ResolvedModule]

    /// The transitive closure of the module dependencies, in build order.
    public lazy var recursiveDependencies: [ResolvedModule] = {
        return try! topologicalSort(self.dependencies, successors: { $0.dependencies })
    }()

    /// The language-level module name.
    public var c99name: String {
        return underlyingModule.c99name
    }

    /// Whether this is a test module.
    public var isTest: Bool {
        return underlyingModule.isTest
    }

    /// The "type" of module.
    public var type: ModuleType {
        return underlyingModule.type
    }

    /// The sources for the module.
    public var sources: Sources {
        return underlyingModule.sources
    }

    /// Create a module instance.
    public init(module: Module, dependencies: [ResolvedModule]) {
        self.underlyingModule = module
        self.dependencies = dependencies
    }

    public var description: String {
        var string = "<ResolvedModule: \(name)"
        if !dependencies.isEmpty {
            string += " deps: \(dependencies.map{$0.name}.joined(separator: ", "))"
        }
        string += ">"
        return string
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

    public init(package: Package, dependencies: [ResolvedPackage], modules: [ResolvedModule], products: [ResolvedProduct]) {
        self.underlyingPackage = package
        self.dependencies = dependencies
        self.modules = modules
        self.products = products
    }

    public var description: String {
        var string = "<ResolvedPackage: \(name)"
        if !dependencies.isEmpty {
            string += " deps: \(dependencies.map{$0.name}.joined(separator: ", "))"
        }
        string += ">"
        return string
    }
}

public final class ResolvedProduct: CustomStringConvertible {

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

    /// Path to the main file for test product on linux.
    public var linuxMainTest: AbsolutePath {
        return underlyingProduct.linuxMainTest
    }

    /// All reachable modules in this product.
    public lazy var allModules: [ResolvedModule] = {
        return try! topologicalSort(self.modules, successors: { $0.dependencies })
    }()

    public init(product: Product, modules: [ResolvedModule]) {
        self.underlyingProduct = product
        self.modules = modules
    }

    public var description: String {
        var string = "<ResolvedPackage: \(name)"
        string += " modules: \(modules.map{$0.name}.joined(separator: ", "))"
        string += ">"
        return string
    }
}
