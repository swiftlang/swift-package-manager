//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// Describes the set of modules that are available to targets within a
/// given package along with the target dependency that's required to import
/// that module into a given
package struct AvailableModules: Codable {
    /// A description of the target dependency that would be needed to
    /// import a given module.
    package enum TargetDependency: Codable {
        case target(name: String)
        case product(name: String, package: String?)

        static func <(lhs: TargetDependency, rhs: TargetDependency) -> Bool {
            switch (lhs, rhs) {
            case (.target(name: let lhsName), .target(name: let rhsName)):
                lhsName < rhsName
            case (.product(name: let lhsName, package: nil),
                  .product(name: let rhsName, package: nil)):
                lhsName < rhsName
            case (.product(name: _, package: nil),
                  .product(name: _, package: _?)):
                true
            case (.product(name: _, package: _?),
                  .product(name: _, package: nil)):
                false
            case (.product(name: let lhsName, package: let lhsPackage?),
                  .product(name: let rhsName, package: let rhsPackage?)):
                (lhsPackage, lhsName) < (rhsPackage, rhsName)
            case (.product, .target):
                false
            case (.target, .product):
                true
            }
        }
    }

    /// The set of modules that are available within the package described by
    /// the manifest, along with the target dependency required to reference
    /// the module.
    package var modules: [String: TargetDependency] = [:]
}

extension ModulesGraph {
    /// A flat list of available modules, used as an intermediary for the
    /// creation of an `AvailableModules` instance.
    fileprivate typealias AvailableModulesList =
        [(String, AvailableModules.TargetDependency)]

    /// Collect the module names that are made available by all of the products
    /// in this package, along with how the target dependency should be
    /// expressed to make the corresponding modules importable.
    ///
    /// The resulting module names are available to any package with a
    /// dependency on this package.
    fileprivate func productsAsAvailableModules(
        from package: ResolvedPackage
    ) -> AvailableModulesList {
        package.products.flatMap { product in
            let productDependency: AvailableModules.TargetDependency = .product(
                name: product.name,
                package: product.packageIdentity.description
            )

            return product.targets.map { target in
                (target.c99name, productDependency)
            }
        }
    }

    /// Collect the module names that are made available by all of the targets
    /// in this package, along with how the target dependency should be
    /// expressed to make the corresponding module importable.
    ///
    /// The resulting module names are available within the targets of this
    /// package.
    fileprivate func targetsAsAvailableModules(
        in package: ResolvedPackage
    ) -> AvailableModulesList {
        package.targets.map { target in
            (target.c99name, .target(name: target.name))
        }
    }

    /// Produce the complete set of modules that are available within the
    /// given resolved package.
    package func availableModules(
        in package: ResolvedPackage
    ) -> AvailableModules {
        var availableModules = AvailableModules()

        // Add available modules from targets within this package.
        availableModules.modules.merge(
            targetsAsAvailableModules(in: package),
            uniquingKeysWith: uniqueTargetDependency
        )

        // Add available modules from the products of any package this package
        // depends on.
        for dependencyID in package.dependencies {
            guard let dependencyPackage = self.package(for: dependencyID) else {
                continue
            }

            availableModules.modules.merge(
                productsAsAvailableModules(from: dependencyPackage),
                uniquingKeysWith: uniqueTargetDependency
            )
        }

        return availableModules
    }
}

/// "Unique" two target dependencies by picking the target dependency that we
/// prefer.
fileprivate func uniqueTargetDependency(
    lhs: AvailableModules.TargetDependency,
    rhs: AvailableModules.TargetDependency
) -> AvailableModules.TargetDependency {
    lhs < rhs ? lhs : rhs
}
