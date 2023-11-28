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

import struct Basics.DiagnosticsEmitter
import struct Basics.ObservabilityMetadata
import class Basics.ObservabilityScope
import protocol PackageModel.PackageConditionProtocol
import struct PackageModel.SupportedPlatforms
import class PackageModel.Target

/// Memoization container for resolved targets.
final class MemoizedResolvedTarget: Memoized<ResolvedTarget> {
    /// Enumeration to represent target dependencies.
    enum Dependency {
        /// Dependency to another target, with conditions.
        case target(_ target: MemoizedResolvedTarget, conditions: [PackageConditionProtocol])

        /// Dependency to a product, with conditions.
        case product(_ product: MemoizedResolvedProduct, conditions: [PackageConditionProtocol])
    }

    /// The target reference.
    let target: Target

    /// DiagnosticsEmitter with which to emit diagnostics
    let diagnosticsEmitter: DiagnosticsEmitter

    /// The target dependencies of this target.
    var dependencies: [Dependency] = []

    /// The defaultLocalization for this package
    var defaultLocalization: String? = nil

    /// The platforms supported by this package.
    var platforms: SupportedPlatforms = .init(declared: [], derivedXCTestPlatformProvider: .none)

    init(
        target: Target,
        observabilityScope: ObservabilityScope
    ) {
        self.target = target
        self.diagnosticsEmitter = observabilityScope.makeDiagnosticsEmitter {
            var metadata = ObservabilityMetadata()
            metadata.targetName = target.name
            return metadata
        }
    }

    func diagnoseInvalidUseOfUnsafeFlags(_ product: ResolvedProduct) throws {
        // Diagnose if any target in this product uses an unsafe flag.
        for target in try product.recursiveTargetDependencies() {
            if target.underlyingTarget.usesUnsafeFlags {
                self.diagnosticsEmitter.emit(.productUsesUnsafeFlags(product: product.name, target: target.name))
            }
        }
    }

    override func constructImpl() throws -> ResolvedTarget {
        let dependencies = try self.dependencies.map { dependency -> ResolvedTarget.Dependency in
            switch dependency {
            case .target(let targetBuilder, let conditions):
                try self.target.validateDependency(target: targetBuilder.target)
                return try .target(targetBuilder.construct(), conditions: conditions)
            case .product(let productBuilder, let conditions):
                try self.target.validateDependency(
                    product: productBuilder.product,
                    productPackage: productBuilder.memoizedPackage.package.identity
                )
                let product = try productBuilder.construct()
                if !productBuilder.memoizedPackage.isAllowedToVendUnsafeProducts {
                    try self.diagnoseInvalidUseOfUnsafeFlags(product)
                }
                return .product(product, conditions: conditions)
            }
        }

        return ResolvedTarget(
            target: self.target,
            dependencies: dependencies,
            defaultLocalization: self.defaultLocalization,
            platforms: self.platforms
        )
    }
}
