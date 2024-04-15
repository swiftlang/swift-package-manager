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

public struct ResolvedProduct {
    /// The name of this product.
    public var name: String {
        self.underlying.name
    }

    /// The type of this product.
    public var type: ProductType {
        self.underlying.type
    }

    public let packageIdentity: PackageIdentity

    /// The underlying product.
    public let underlying: Product

    /// The top level modules contained in this product.
    public let modules: IdentifiableSet<ResolvedModule>

    @available(*, deprecated, renamed: "modules")
    public var targets: IdentifiableSet<ResolvedModule> { self.modules }

    /// Executable target for test entry point file.
    public let testEntryPointTarget: ResolvedModule?

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this product.
    public let supportedPlatforms: [SupportedPlatform]

    public let platformVersionProvider: PlatformVersionProvider

    /// Triple for which this resolved product should be compiled for.
    public let buildTriple: BuildTriple

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableTarget: ResolvedModule {
        get throws {
            guard self.type == .executable || self.type == .snippet || self.type == .macro else {
                throw InternalError("`executableTarget` should only be called for executable targets")
            }
            guard let underlyingExecutableTarget = modules.map(\.underlying).executables.first,
                  let executableTarget = modules.first(where: { $0.underlying == underlyingExecutableTarget })
            else {
                throw InternalError("could not determine executable target")
            }
            return executableTarget
        }
    }

    @available(*, deprecated, renamed: "init(packageIdentity:product:modules:)")
    public init(packageIdentity: PackageIdentity, product: Product, targets: IdentifiableSet<ResolvedModule>) {
        self.init(packageIdentity: packageIdentity, product: product, modules: targets)
    }

    public init(packageIdentity: PackageIdentity, product: Product, modules: IdentifiableSet<ResolvedModule>) {
        assert(product.targets.count == modules.count && product.targets.map(\.name).sorted() == modules.map(\.name).sorted())
        self.packageIdentity = packageIdentity
        self.underlying = product
        self.modules = modules

        // defaultLocalization is currently shared across the entire package
        // this may need to be enhanced if / when we support localization per target or product
        let defaultLocalization = self.modules.first?.defaultLocalization
        self.defaultLocalization = defaultLocalization

        let (platforms, platformVersionProvider) = Self.computePlatforms(targets: modules)
        self.supportedPlatforms = platforms
        self.platformVersionProvider = platformVersionProvider

        self.testEntryPointTarget = product.testEntryPointPath.map { testEntryPointPath in
            // Create an executable resolved target with the entry point file, adding product's targets as dependencies.
            let dependencies: [Target.Dependency] = product.targets.map { .target($0, conditions: []) }
            let swiftTarget = SwiftTarget(
                name: product.name,
                dependencies: dependencies,
                packageAccess: true, // entry point target so treated as a part of the package
                testEntryPointPath: testEntryPointPath
            )
            return ResolvedModule(
                packageIdentity: packageIdentity,
                underlying: swiftTarget,
                dependencies: modules.map { .module($0, conditions: []) },
                defaultLocalization: defaultLocalization ?? .none, // safe since this is a derived product
                supportedPlatforms: platforms,
                platformVersionProvider: platformVersionProvider
            )
        }
        
        self.buildTriple = .destination
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
        self.modules.contains { $0.underlying is SwiftTarget }
    }

    /// Returns the recursive module dependencies.
    public func recursiveModuleDependencies() throws -> [ResolvedModule] {
        let recursiveDependencies = try self.modules.lazy.flatMap { try $0.recursiveModuleDependencies() }
        return Array(IdentifiableSet(self.modules).union(recursiveDependencies))
    }

    @available(*, deprecated, renamed: "recursiveModuleDependencies")
    public func recursiveTargetDependencies() throws -> [ResolvedModule] {
        try self.recursiveModuleDependencies()
    }

    private static func computePlatforms(
        targets: IdentifiableSet<ResolvedModule>
    ) -> ([SupportedPlatform], PlatformVersionProvider) {
        let declaredPlatforms = targets.reduce(into: [SupportedPlatform]()) { partial, item in
            merge(into: &partial, platforms: item.supportedPlatforms)
        }

        return (
            declaredPlatforms.sorted(by: { $0.platform.name < $1.platform.name }),
            PlatformVersionProvider(implementation: .mergingFromTargets(targets))
        )
    }

    public func getSupportedPlatform(for platform: Platform, usingXCTest: Bool) -> SupportedPlatform {
        self.platformVersionProvider.getDerived(
            declared: self.supportedPlatforms,
            for: platform,
            usingXCTest: usingXCTest
        )
    }

    func diagnoseInvalidUseOfUnsafeFlags(_ diagnosticsEmitter: DiagnosticsEmitter) throws {
        // Diagnose if any module in this product uses an unsafe flag.
        for module in try self.recursiveModuleDependencies() {
            if module.underlying.usesUnsafeFlags {
                diagnosticsEmitter.emit(.productUsesUnsafeFlags(product: self.name, target: module.name))
            }
        }
    }
}

extension ResolvedProduct: CustomStringConvertible {
    public var description: String {
        "<ResolvedProduct: \(self.name)>"
    }
}

extension ResolvedProduct {
    public var isLinkingXCTest: Bool {
        // To retain existing behavior, we have to check both the product type, as well as the types of all of its
        // targets.
        self.type == .test || self.modules.contains(where: { $0.type == .test })
    }
}

extension ResolvedProduct: Identifiable {
    /// Resolved target identity that uniquely identifies it in a resolution graph.
    public struct ID: Hashable {
        public let targetName: String
        let packageIdentity: PackageIdentity
        public let buildTriple: BuildTriple
    }

    public var id: ID {
        ID(targetName: self.name, packageIdentity: self.packageIdentity, buildTriple: self.buildTriple)
    }
}

@available(*, unavailable, message: "Use `Identifiable` conformance or `IdentifiableSet` instead")
extension ResolvedProduct: Hashable {}
