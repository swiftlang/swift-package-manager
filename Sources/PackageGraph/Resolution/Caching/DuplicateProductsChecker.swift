//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Basics.ObservabilityScope
import struct PackageModel.PackageIdentity

struct DuplicateProductsChecker {
    private var packageIDToCachedPackage = [PackageIdentity: CachedResolvedPackage]()
    private var checkedPkgIDs = [PackageIdentity]()

    private let moduleAliasingUsed: Bool
    private let observabilityScope: ObservabilityScope

    init(cachedPackages: [CachedResolvedPackage], moduleAliasingUsed: Bool, observabilityScope: ObservabilityScope) {
        for cachedPackage in cachedPackages {
            let pkgID = cachedPackage.package.identity
            self.packageIDToCachedPackage[pkgID] = cachedPackage
        }
        self.moduleAliasingUsed = moduleAliasingUsed
        self.observabilityScope = observabilityScope
    }

    mutating func run(lookupByProductIDs: Bool = false, observabilityScope: ObservabilityScope) throws {
        var productToPkgMap = [String: Set<PackageIdentity>]()
        for (pkgID, cachedPackage) in self.packageIDToCachedPackage {
            let useProductIDs = cachedPackage.package.manifest.disambiguateByProductIDs || lookupByProductIDs
            let depProductRefs = cachedPackage.package.targets.map(\.dependencies).flatMap { $0 }.compactMap(\.product)
            for depRef in depProductRefs {
                if let depPkg = depRef.package.map(PackageIdentity.plain) {
                    if !self.checkedPkgIDs.contains(depPkg) {
                        self.checkedPkgIDs.append(depPkg)
                    }
                    let depProductIDs = self.packageIDToCachedPackage[depPkg]?.package.products
                        .filter { $0.identity == depRef.identity }
                        .map { useProductIDs && $0.isDefaultLibrary ? $0.identity : $0.name } ?? []
                    for depID in depProductIDs {
                        productToPkgMap[depID, default: .init()].insert(depPkg)
                    }
                } else {
                    let depPkgs = cachedPackage.dependencies
                        .filter { $0.products.contains { $0.product.name == depRef.name }}
                        .map(\.package.identity)
                    productToPkgMap[depRef.name, default: .init()].formUnion(Set(depPkgs))
                    self.checkedPkgIDs.append(contentsOf: depPkgs)
                }
                if !self.checkedPkgIDs.contains(pkgID) {
                    self.checkedPkgIDs.append(pkgID)
                }
            }
            for (depIDOrName, depPkgs) in productToPkgMap.filter({ Set($0.value).count > 1 }) {
                let name = depIDOrName.components(separatedBy: "_").dropFirst().joined(separator: "_")
                throw emitDuplicateProductDiagnostic(
                    productName: name.isEmpty ? depIDOrName : name,
                    packages: depPkgs.compactMap { self.packageIDToCachedPackage[$0]?.package },
                    moduleAliasingUsed: self.moduleAliasingUsed,
                    observabilityScope: self.observabilityScope
                )
            }
        }

        // Check packages that exist but are not in a dependency graph
        let untrackedPkgs = self.packageIDToCachedPackage.filter { !self.checkedPkgIDs.contains($0.key) }
        for (pkgID, cachedPackage) in untrackedPkgs {
            for product in cachedPackage.products {
                // Check if checking product ID only is safe
                let useIDOnly = lookupByProductIDs && product.product.isDefaultLibrary
                if !useIDOnly {
                    // This untracked pkg could have a product name conflicting with a
                    // product name from another package, but since it's not depended on
                    // by other packages, keep track of both this product's name and ID
                    // just in case other packages are < .v5_8
                    productToPkgMap[product.product.name, default: .init()].insert(pkgID)
                }
                productToPkgMap[product.product.identity, default: .init()].insert(pkgID)
            }
        }

        let duplicates = productToPkgMap.filter { $0.value.count > 1 }
        for (productName, pkgs) in duplicates {
            throw emitDuplicateProductDiagnostic(
                productName: productName,
                packages: pkgs.compactMap { self.packageIDToCachedPackage[$0]?.package },
                moduleAliasingUsed: self.moduleAliasingUsed,
                observabilityScope: self.observabilityScope
            )
        }
    }
}
