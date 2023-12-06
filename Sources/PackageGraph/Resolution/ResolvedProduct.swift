//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
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

    /// Executable target for test entry point file.
    public let testEntryPointTarget: ResolvedTarget?

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this product.
    public let platforms: SupportedPlatforms

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableTarget: ResolvedTarget {
        get throws {
            guard type == .executable || type == .snippet || type == .macro else {
                throw InternalError("`executableTarget` should only be called for executable targets")
            }
            guard let underlyingExecutableTarget = targets.map({ $0.underlyingTarget }).executables.first, let executableTarget = targets.first(where: { $0.underlyingTarget == underlyingExecutableTarget }) else {
                throw InternalError("could not determine executable target")
            }
            return executableTarget
        }
    }

    public init(product: Product, targets: [ResolvedTarget]) {
        assert(product.targets.count == targets.count && product.targets.map({ $0.name }) == targets.map({ $0.name }))
        self.underlyingProduct = product
        self.targets = targets

        // defaultLocalization is currently shared across the entire package
        // this may need to be enhanced if / when we support localization per target or product
        let defaultLocalization = self.targets.first?.defaultLocalization
        self.defaultLocalization = defaultLocalization

        let platforms = Self.computePlatforms(targets: targets)
        self.platforms = platforms

        self.testEntryPointTarget = underlyingProduct.testEntryPointPath.map { testEntryPointPath in
            // Create an executable resolved target with the entry point file, adding product's targets as dependencies.
            let dependencies: [Target.Dependency] = product.targets.map { .target($0, conditions: []) }
            let swiftTarget = SwiftTarget(name: product.name,
                                          dependencies: dependencies,
                                          packageAccess: true, // entry point target so treated as a part of the package
                                          testEntryPointPath: testEntryPointPath)
            return ResolvedTarget(
                target: swiftTarget,
                dependencies: targets.map { .target($0, conditions: []) },
                defaultLocalization: defaultLocalization ?? .none, // safe since this is a derived product
                platforms: platforms
            )
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

    private static func computePlatforms(targets: [ResolvedTarget]) -> SupportedPlatforms {
        // merging two sets of supported platforms, preferring the max constraint
        func merge(into partial: inout [SupportedPlatform], platforms: [SupportedPlatform]) {
            for platformSupport in platforms {
                if let existing = partial.firstIndex(where: { $0.platform == platformSupport.platform }) {
                    if partial[existing].version < platformSupport.version {
                        partial.remove(at: existing)
                        partial.append(platformSupport)
                    }
                } else {
                    partial.append(platformSupport)
                }
            }
        }

        let declared = targets.reduce(into: [SupportedPlatform]()) { partial, item in
            merge(into: &partial, platforms: item.platforms.declared)
        }

        return SupportedPlatforms(
            declared: declared.sorted(by: { $0.platform.name < $1.platform.name })) { declared in
                let platforms = targets.reduce(into: [SupportedPlatform]()) { partial, item in
                    merge(into: &partial, platforms: [item.platforms.getDerived(for: declared, usingXCTest: item.type == .test)])
                }
                return platforms.first!.version
            }
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

extension ResolvedProduct {
    public var isLinkingXCTest: Bool {
        // To retain existing behavior, we have to check both the product type, as well as the types of all of its targets.
        return self.type == .test || self.targets.contains(where: { $0.type == .test })
    }
}
