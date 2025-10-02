//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

import struct Basics.IdentifiableSet

import PackageModel
import PackageGraph

public func PackageGraphTester(_ graph: ModulesGraph, _ result: (PackageGraphResult) throws -> Void) rethrows {
    try result(PackageGraphResult(graph))
}

public final class PackageGraphResult {
    public let graph: ModulesGraph

    public init(_ graph: ModulesGraph) {
        self.graph = graph
    }

    public func check(roots: PackageIdentity..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(graph.rootPackages.map{$0.identity }.sorted() == roots.sorted(), sourceLocation: sourceLocation)
    }

    public func check(packages: PackageIdentity..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(graph.packages.map {$0.identity }.sorted() == packages.sorted(), sourceLocation: sourceLocation)
    }

    public func check(modules: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            graph.allModules
                .filter { $0.type != .test }
                .map { $0.name }
                .sorted() == modules.sorted(), sourceLocation: sourceLocation)
    }

    public func check(products: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(graph.allProducts.map { $0.name }) == Set(products), sourceLocation: sourceLocation)
    }

    public func check(reachableTargets: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(graph.reachableModules.map { $0.name }) == Set(reachableTargets), sourceLocation: sourceLocation)
    }

    public func check(reachableProducts: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(graph.reachableProducts.map { $0.name }) == Set(reachableProducts), sourceLocation: sourceLocation)
    }

    public func check(
        reachableBuildTargets: String...,
        in environment: BuildEnvironment,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let targets = Set(try self.reachableBuildTargets(in: environment).map({ $0.name }))
        #expect(targets == Set(reachableBuildTargets), sourceLocation: sourceLocation)
    }

    public func check(
        reachableBuildProducts: String...,
        in environment: BuildEnvironment,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let products = Set(try self.reachableBuildProducts(in: environment).map({ $0.name }))
        #expect(products == Set(reachableBuildProducts), sourceLocation: sourceLocation)
    }

    public func checkTarget(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedTargetResult) throws -> Void
    ) throws {
        let target = try #require(graph.module(for: name), "Target \(name) not found", sourceLocation: sourceLocation)

        try body(ResolvedTargetResult(target))
    }

    package func checkTargets(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: ([ResolvedTargetResult]) throws -> Void
    ) rethrows {
        try body(graph.allModules.filter { $0.name == name }.map(ResolvedTargetResult.init))
    }

    public func checkProduct(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedProductResult) -> Void
    ) throws {
        let product = try #require(graph.product(for: name), "Product \(name) not found", sourceLocation: sourceLocation)


        body(ResolvedProductResult(product))
    }

    package func checkPackage(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedPackage) -> Void
    ) throws {
        let pkg = try #require(find(package: .init(stringLiteral: name)), "Product \(name) not found", sourceLocation: sourceLocation)
        body(pkg)
    }

    public func check(testModules: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            graph.allModules
                .filter{ $0.type == .test }
                .map{ $0.name }
                .sorted() == testModules.sorted(), sourceLocation: sourceLocation)
    }

    public func find(package: PackageIdentity) -> ResolvedPackage? {
        return graph.package(for: package)
    }

    private func reachableBuildTargets(in environment: BuildEnvironment) throws -> IdentifiableSet<ResolvedModule> {
        let inputTargets = graph.inputPackages.lazy.flatMap { $0.modules }
        let recursiveBuildTargetDependencies = try inputTargets
            .flatMap { try $0.recursiveDependencies(satisfying: environment) }
            .compactMap { $0.module }
        return IdentifiableSet(inputTargets).union(recursiveBuildTargetDependencies)
    }

    private func reachableBuildProducts(in environment: BuildEnvironment) throws -> IdentifiableSet<ResolvedProduct> {
        let recursiveBuildProductDependencies = try graph.inputPackages
            .lazy
            .flatMap { $0.modules }
            .flatMap { try $0.recursiveDependencies(satisfying: environment) }
            .compactMap { $0.product }
        return IdentifiableSet(graph.inputPackages.flatMap { $0.products }).union(recursiveBuildProductDependencies)
    }
}

public final class ResolvedTargetResult {
    public let target: ResolvedModule

    init(_ target: ResolvedModule) {
        self.target = target
    }

    public func check(dependencies: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(dependencies) == Set(target.dependencies.map({ $0.name })), sourceLocation: sourceLocation)
    }

    public func check(dependencies: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(dependencies) == Set(target.dependencies.map({ $0.name })), sourceLocation: sourceLocation)
    }

    public func checkDependency(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedTargetDependencyResult) -> Void
    ) throws {
        let dependency = try #require(
            target.dependencies.first(where: { $0.name == name }),
            "Dependency \(name) not found",
            sourceLocation: sourceLocation,
        )
        body(ResolvedTargetDependencyResult(dependency))
    }

    public func check(type: Module.Kind, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(type == target.type, sourceLocation: sourceLocation)
    }

    public func checkDeclaredPlatforms(_ platforms: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
        let targetPlatforms = Dictionary(
            uniqueKeysWithValues: target.supportedPlatforms.map { ($0.platform.name, $0.version.versionString) }
        )
        #expect(platforms == targetPlatforms, sourceLocation: sourceLocation)
    }

    public func checkDerivedPlatforms(_ platforms: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
        let derived = platforms.map {
            let platform = PlatformRegistry.default.platformByName[$0.key] ?? PackageModel.Platform
                .custom(name: $0.key, oldestSupportedVersion: $0.value)
            return self.target.getSupportedPlatform(for: platform, usingXCTest: self.target.type == .test)
        }
        let targetPlatforms = Dictionary(
            uniqueKeysWithValues: derived.map { ($0.platform.name, $0.version.versionString) }
        )
        #expect(platforms == targetPlatforms, sourceLocation: sourceLocation)
    }

    public func checkDerivedPlatformOptions(
        _ platform: PackageModel.Platform,
        options: [String],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let platform = self.target.getSupportedPlatform(for: platform, usingXCTest: target.type == .test)
        #expect(platform.options == options, sourceLocation: sourceLocation)
    }

    package func checkBuildSetting(
        declaration: BuildSettings.Declaration,
        assignments: Set<BuildSettings.Assignment>?,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        #expect(
            target.underlying.buildSettings.assignments[declaration].flatMap { Set($0) } == assignments,
            sourceLocation: sourceLocation
        )
    }
}

public final class ResolvedTargetDependencyResult {
    private let dependency: ResolvedModule.Dependency

    init(_ dependency: ResolvedModule.Dependency) {
        self.dependency = dependency
    }

    public func checkConditions(satisfy environment: BuildEnvironment, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(dependency.conditions.allSatisfy({ $0.satisfies(environment) }), sourceLocation: sourceLocation)
    }

    public func checkConditions(
        dontSatisfy environment: BuildEnvironment,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        #expect(!dependency.conditions.allSatisfy({ $0.satisfies(environment) }), sourceLocation: sourceLocation)
    }

    public func checkTarget(
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedTargetResult) throws -> Void
    ) throws {
        guard case let .module(target, _) = self.dependency else {
            Issue.record("Dependency \(dependency) is not a target", sourceLocation: sourceLocation)
            return
        }
        try body(ResolvedTargetResult(target))
    }

    public func checkProduct(
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedProductResult) -> Void
    ) {
        guard case let .product(product, _) = self.dependency else {
             Issue.record("Dependency \(dependency) is not a product", sourceLocation: sourceLocation)
             return
        }
        body(ResolvedProductResult(product))
    }
}

public final class ResolvedProductResult {
    private let product: ResolvedProduct

    init(_ product: ResolvedProduct) {
        self.product = product
    }

    public func check(modules: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(modules) == Set(product.modules.map({ $0.name })), sourceLocation: sourceLocation)
    }

    public func check(type: ProductType, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(type == product.type, sourceLocation: sourceLocation)
    }

    public func checkDeclaredPlatforms(_ platforms: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
        let targetPlatforms = Dictionary(uniqueKeysWithValues: product.supportedPlatforms.map({ ($0.platform.name, $0.version.versionString) }))
        #expect(platforms == targetPlatforms, sourceLocation: sourceLocation)
    }

    public func checkDerivedPlatforms(_ platforms: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
        let derived = platforms.map {
            let platform = PlatformRegistry.default.platformByName[$0.key] ?? PackageModel.Platform.custom(name: $0.key, oldestSupportedVersion: $0.value)
            return product.getSupportedPlatform(for: platform, usingXCTest: product.isLinkingXCTest)
        }
        let targetPlatforms = Dictionary(uniqueKeysWithValues: derived.map({ ($0.platform.name, $0.version.versionString) }))
        #expect(platforms == targetPlatforms, sourceLocation: sourceLocation)
    }

    public func checkDerivedPlatformOptions(_ platform: PackageModel.Platform, options: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        let platform = product.getSupportedPlatform(for: platform, usingXCTest: product.isLinkingXCTest)
        #expect(platform.options == options, sourceLocation: sourceLocation)
    }

    public func checkTarget(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (ResolvedTargetResult) throws -> Void
    ) throws {
        let target = try #require(
            product.modules.first(where: { $0.name == name }),
            "Target \(name) not found",
            sourceLocation: sourceLocation,
        )
        try body(ResolvedTargetResult(target))
    }
}

extension ResolvedModule.Dependency {
    public var name: String {
        switch self {
        case .module(let target, _):
            return target.name
        case .product(let product, _):
            return product.name
        }
    }
}
