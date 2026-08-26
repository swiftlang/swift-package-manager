//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SPMBuildCore
import PackageGraph
import PackageModel

import struct Basics.Diagnostic

extension BuildConfiguration {
    public var swiftbuildName: String {
        switch self {
        case .debug: "Debug"
        case .release: "Release"
        }
    }
}

extension BuildSubset {
    @_spi(SwiftPMTesting)
    public func pifTargetName(for graph: ModulesGraph) -> String {
        switch self {
        case .product(let name, _, let package):
            // When `package` disambiguates a product name that could
            // otherwise collide with the same-named product in a sibling
            // workspace member, look up the specific package's product
            // in the graph and use its canonical PIF target name. When
            // `package` is nil (or the specified member is missing from
            // the graph), fall through to a graph-wide lookup that
            // resolves the qualifying package by product name — first
            // among root packages, then across the whole graph so
            // executables provided by transitive dependencies remain
            // reachable via `swift run`.
            if let package,
               let qualifiedPackage = graph.rootPackages.first(where: { $0.identity == package }),
               let qualifiedProduct = qualifiedPackage.products.first(where: { $0.name == name })
            {
                return PackagePIFBuilder.targetName(
                    forProductName: qualifiedProduct.name,
                    packageIdentity: qualifiedPackage.identity,
                )
            }
            if let inferred = graph.rootPackages
                .flatMap({ pkg in pkg.products.filter { $0.name == name }.map { (pkg, $0) } })
                .first
            {
                return PackagePIFBuilder.targetName(
                    forProductName: inferred.1.name,
                    packageIdentity: inferred.0.identity,
                )
            }
            if let dependencyProduct = graph.allProducts.first(where: { $0.name == name }) {
                return PackagePIFBuilder.targetName(
                    forProductName: dependencyProduct.name,
                    packageIdentity: dependencyProduct.packageIdentity,
                )
            }
            // No matching product found — return an unqualified name
            // (Swift Build will subsequently emit its own not-found
            // diagnostic).
            return "\(name)-product"
        case .target(let name, _, let package):
            // If the named target is the main module of a main-module product (e.g. a test or
            // executable target), it is represented in the PIF by that product's target.
            let candidateProducts: [ResolvedProduct]
            if let package {
                candidateProducts = graph.rootPackages
                    .first(where: { $0.identity == package })
                    .map { Array($0.products) } ?? []
            } else {
                candidateProducts = Array(graph.allProducts)
            }
            if let product = candidateProducts.first(where: {
                $0.isMainModuleProduct
                    && $0.mainModule?.name == name
                    && !($0.mainModule?.isTestSupportModule ?? false)
            }) {
                return PackagePIFBuilder.targetName(
                    forProductName: product.name,
                    packageIdentity: product.packageIdentity,
                )
            }
            return name
        case .allExcludingTests(nil):
            return PIFBuilder.allExcludingTestsTargetName
        case .allIncludingTests(nil):
            return PIFBuilder.allIncludingTestsTargetName
        case .allExcludingTests(let identity?), .workspaceMember(let identity):
            // Both forms name "the non-test build products of a single
            // workspace member". `.workspaceMember(X)` is preserved as
            // the semantic-clarity spelling; downstream routing treats
            // it identically to `.allExcludingTests(package: X)`.
            return PIFBuilder.workspaceMemberTargetName(for: identity)
        case .allIncludingTests(.some):
            // TODO(Slice 6): route to a per-member tests aggregate.
            // Currently falls back to the workspace-wide
            // `AllIncludingTests` — a superset of the user's intent
            // rather than a wrong-behavior. Refined in Slice 6.
            return PIFBuilder.allIncludingTestsTargetName
        }
    }
}
