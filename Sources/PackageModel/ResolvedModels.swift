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

    /// Create an executable module for linux main test manifest file.
    public func createLinuxMainModule() -> ResolvedModule {
        precondition(type == .test, "This property is only valid for test product type")
        // FIXME: This is hacky, we should get this from somewhere else.
        let testDirectory = modules.first{ $0.type == .test }!.sources.root.parentDirectory
        // Path to the main file for test product on linux.
        let linuxMain = testDirectory.appending(component: "LinuxMain.swift")
        // Create an exectutable resolved module with the linux main, adding product's modules as dependencies.
        let swiftModule = SwiftModule(
            linuxMain: linuxMain, name: name, dependencies: underlyingProduct.modules)

        return ResolvedModule(module: swiftModule, dependencies: modules)
    }

    /// All reachable modules in this product.
    public lazy var allModules: [ResolvedModule] = {
        return try! topologicalSort(self.modules, successors: { $0.dependencies })
    }()

    /// The main executable module of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableModule: ResolvedModule {
        precondition(type == .executable, "This property should only be called for executable modules")
        return modules.first{$0.type == .executable}!
    }

    public init(product: Product, modules: [ResolvedModule]) {
        assert(product.modules.count == modules.count && product.modules.map{$0.name} == modules.map{$0.name})
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
