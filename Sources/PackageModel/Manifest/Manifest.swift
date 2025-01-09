//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

import func TSCBasic.transitiveClosure

import struct TSCUtility.Version

/// This contains the declarative specification loaded from package manifest
/// files, and the tools for working with the manifest.
public final class Manifest: Sendable {
    /// The standard filename for the manifest.
    public static let filename = basename + ".swift"

    /// The standard basename for the manifest.
    public static let basename = "Package"

    /// The name of the package as it appears in the manifest
    /// FIXME: deprecate this, there is no value in this once we have real package identifiers
    public let displayName: String

    // FIXME: deprecate this, this is not part of the manifest information, we just use it as a container for this data
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    //
    /// The path of the manifest file.
    // @available(*, deprecated)
    public let path: AbsolutePath

    // FIXME: deprecate this, this is not part of the manifest information, we just use it as a container for this data
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    //
    /// The repository URL the manifest was loaded from.
    public let packageLocation: String

    /// The canonical repository URL the manifest was loaded from.
    public var canonicalPackageLocation: CanonicalPackageLocation {
        CanonicalPackageLocation(self.packageLocation)
    }

    /// Whether kind of package this manifest is from.
    public let packageKind: PackageReference.Kind

    /// The version this package was loaded from, if known.
    public let version: Version?

    /// The revision this package was loaded from, if known.
    public let revision: String?

    /// The tools version declared in the manifest.
    public let toolsVersion: ToolsVersion

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The declared platforms in the manifest.
    public let platforms: [PlatformDescription]

    /// The declared package dependencies.
    public let dependencies: [PackageDependency]

    /// The targets declared in the manifest.
    public let targets: [TargetDescription]

    /// The targets declared in the manifest, keyed by their name.
    public let targetMap: [String: TargetDescription]

    /// The products declared in the manifest.
    public let products: [ProductDescription]

    /// The set of traits of this package.
    public let traits: Set<TraitDescription>

    /// The configuration of enabled traits of this package.
    public let enabledTraits: Set<TraitDescription>?

    /// The C language standard flag.
    public let cLanguageStandard: String?

    /// The C++ language standard flag.
    public let cxxLanguageStandard: String?

    /// The supported Swift language versions of the package.
    public let swiftLanguageVersions: [SwiftLanguageVersion]?

    /// The pkg-config name of a system package.
    public let pkgConfig: String?

    /// The system package providers of a system package.
    public let providers: [SystemPackageProviderDescription]?

    /// Targets required for building particular product filters.
    private let _requiredTargets = ThreadSafeKeyValueStore<ProductFilter, [TargetDescription]>()

    /// Dependencies required for building particular product filters.
    private let _requiredDependencies = ThreadSafeKeyValueStore<ProductFilter, [PackageDependency]>()

    public init(
        displayName: String,
        path: AbsolutePath,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        defaultLocalization: String?,
        platforms: [PlatformDescription],
        version: TSCUtility.Version?,
        revision: String?,
        toolsVersion: ToolsVersion,
        pkgConfig: String?,
        providers: [SystemPackageProviderDescription]?,
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        swiftLanguageVersions: [SwiftLanguageVersion]?,
        dependencies: [PackageDependency] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = [],
        traits: Set<TraitDescription>,
        enabledTraits: Set<TraitDescription> = []
    ) {
        self.displayName = displayName
        self.path = path
        self.packageKind = packageKind
        self.packageLocation = packageLocation
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms
        self.version = version
        self.revision = revision
        self.toolsVersion = toolsVersion
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.swiftLanguageVersions = swiftLanguageVersions
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
        self.targetMap = Dictionary(targets.lazy.map { ($0.name, $0) }, uniquingKeysWith: { $1 })
        self.traits = traits
        // TODO: pass config in init
        self.enabledTraits = enabledTraits
    }

    /// Returns the targets required for a particular product filter.
    public func targetsRequired(for productFilter: ProductFilter) -> [TargetDescription] {
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        // If we have already calculated it, returned the cached value.
        if let targets = _requiredTargets[productFilter] {
            return targets
        } else {
            let targets: [TargetDescription]
            switch productFilter {
            case .everything:
                return self.targets
            case .specific(let productFilter):
                let products = self.products.filter { productFilter.contains($0.name) }
                targets = self.targetsRequired(for: products)
            }

            self._requiredTargets[productFilter] = targets
            return targets
        }
        #else
        // using .nothing as cache key while ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION is false
        if let targets = self._requiredTargets[.nothing] {
            return targets
        } else {
            let targets = self.packageKind.isRoot ? self.targets : self.targetsRequired(for: self.products)
            // using .nothing as cache key while ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION is false
            self._requiredTargets[.nothing] = targets
            return targets
        }
        #endif
    }

    /// Returns the package dependencies required for a particular products filter.
    public func dependenciesRequired(for productFilter: ProductFilter) -> [PackageDependency] {
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        // If we have already calculated it, returned the cached value.
        if let dependencies = self._requiredDependencies[productFilter] {
            return dependencies
        } else {
            let targets = self.targetsRequired(for: productFilter)
            let dependencies = self.dependenciesRequired(for: targets, keepUnused: productFilter == .everything)
            self._requiredDependencies[productFilter] = dependencies
            return dependencies
        }
        #else
        guard self.toolsVersion >= .v5_2 && !self.packageKind.isRoot else {
            return self.dependencies
        }

        // using .nothing as cache key while ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION is false
        if let dependencies = self._requiredDependencies[.nothing] {
            return dependencies
        } else {
            var requiredDependencies: Set<PackageIdentity> = []
            for target in self.targetsRequired(for: self.products) {
                for targetDependency in target.dependencies {
                    guard self.isTargetDependencyEnabled(targetDependency) else { continue }
                    if let dependency = self.packageDependency(referencedBy: targetDependency) {
                        requiredDependencies.insert(dependency.identity)
                    }
                }

                target.pluginUsages?.forEach {
                    if let dependency = self.packageDependency(referencedBy: $0) {
                        requiredDependencies.insert(dependency.identity)
                    }
                }
            }

            let dependencies = self.dependencies.filter { requiredDependencies.contains($0.identity) }
            // using .nothing as cache key while ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION is false
            self._requiredDependencies[.nothing] = dependencies
            return dependencies
        }
        #endif
    }

    /// Returns the targets required for building the provided products.
    public func targetsRequired(for products: [ProductDescription]) -> [TargetDescription] {
        let productsByName = Dictionary(products.map { ($0.name, $0) }, uniquingKeysWith: { $1 })
        let targetsByName = Dictionary(targets.map { ($0.name, $0) }, uniquingKeysWith: { $1 })
        let productTargetNames = products.flatMap(\.targets)

        let dependentTargetNames = transitiveClosure(productTargetNames, successors: { targetName in

            if let target = targetsByName[targetName] {
                let dependencies: [String] = target.dependencies.compactMap { dependency in
                    switch dependency {
                    case .target(let name, _),
                         .byName(let name, _):
                        return targetsByName.keys.contains(name) ? name : nil
                    default:
                        return nil
                    }
                }

                let plugins: [String] = target.pluginUsages?.compactMap { pluginUsage in
                    switch pluginUsage {
                    case .plugin(name: let name, package: nil):
                        if targetsByName.keys.contains(name) {
                            return name
                        } else if let targetName = productsByName[name]?.targets.first {
                            return targetName
                        } else {
                            return nil
                        }
                    default:
                        return nil
                    }
                } ?? []

                return dependencies + plugins
            }

            return []

        })

        let requiredTargetNames = Set(productTargetNames).union(dependentTargetNames)
        let requiredTargets = requiredTargetNames.compactMap { targetsByName[$0] }
        return requiredTargets
    }

    /// Returns the package dependencies required for building the provided targets.
    ///
    /// The returned dependencies have their particular product filters registered. (To determine product filters
    /// without removing any dependencies from the list, specify `keepUnused: true`.)
    private func dependenciesRequired(
        for targets: [TargetDescription],
        keepUnused: Bool = false
    ) -> [PackageDependency] {
        var registry: (known: [PackageIdentity: ProductFilter], unknown: Set<String>) = ([:], [])
        let availablePackages = Set(self.dependencies.lazy.map(\.identity))

        for target in targets {
            for targetDependency in target.dependencies {
                self.register(
                    targetDependency: targetDependency,
                    registry: &registry,
                    availablePackages: availablePackages
                )
            }
            for requiredPlugIn in target.pluginUsages ?? [] {
                self.register(requiredPlugIn: requiredPlugIn, registry: &registry, availablePackages: availablePackages)
            }
        }

        // Products whose package could not be determined are marked as needed on every dependency.
        // (This way none of them filters such a product out.)
        var associations = registry.known
        let unknown = registry.unknown
        if !registry.unknown.isEmpty {
            for package in availablePackages {
                associations[package, default: .nothing].formUnion(.specific(unknown))
            }
        }

        return self.dependencies.compactMap { dependency in
            if let filter = associations[dependency.identity] {
                return dependency.filtered(by: filter)
            } else if keepUnused {
                // Register that while the dependency was kept, no products are needed.
                return dependency.filtered(by: .nothing)
            } else {
                // Dependencies known to not have any relevant products are discarded.
                return nil
            }
        }
    }

    /// Finds the package dependency referenced by the specified target dependency.
    /// - Returns: Returns `nil` if the dependency is a target dependency, if it is a product dependency but has no
    /// package name (for tools versions less than 5.2), or if there were no dependencies with the provided name.
    public func packageDependency(
        referencedBy targetDependency: TargetDescription.Dependency
    ) -> PackageDependency? {
        let packageName: String

        switch targetDependency {
        case .product(_, package: let name?, _, _),
             .byName(name: let name, _):
            packageName = name
        default:
            return nil
        }

        return self.packageDependency(referencedBy: packageName)
    }

    /// Finds the package dependency referenced by the specified plugin usage.
    /// - Returns: Returns `nil` if  the used plugin is from the same package or if the package the used plugin is from cannot be found.
    public func packageDependency(
        referencedBy pluginUsage: TargetDescription.PluginUsage
    ) -> PackageDependency? {
        switch pluginUsage {
        case .plugin(_, .some(let package)):
            return self.packageDependency(referencedBy: package)
        default:
            return nil
        }
    }

    private func packageDependency(
        referencedBy packageName: String
    ) -> PackageDependency? {
        // TODO: assure that the dependency is activated by the set of traits that are enabled
        self.dependencies.first(where: {
            // rdar://80594761 make sure validation is case insensitive
            $0.nameForModuleDependencyResolutionOnly.lowercased() == packageName.lowercased()
        })
    }

    /// Returns the package identity referred to by a target dependency string.
    ///
    /// This first checks if any declared package names (from 5.2) match.
    /// If none is found, it is assumed that the string is the package identity itself
    /// (although it may actually be a dangling reference diagnosed later).
    private func packageIdentity(referencedBy packageName: String) -> PackageIdentity {
        self.packageDependency(referencedBy: packageName)?.identity
            ?? .plain(packageName)
    }

    /// Registers a required product with a particular dependency if possible, or registers it as unknown.
    ///
    /// - Parameters:
    ///   - targetDependency: The target dependency to register.
    ///   - registry: The registry in which to record the association.
    ///   - availablePackages: The set of available packages.
    private func register(
        targetDependency: TargetDescription.Dependency,
        registry: inout (known: [PackageIdentity: ProductFilter], unknown: Set<String>),
        availablePackages: Set<PackageIdentity>
    ) {
        switch targetDependency {
        case .target:
            break
        case .product(let product, let package, _, _):
            if let package { // ≥ 5.2
                if !self.register(
                    product: product,
                    inPackage: self.packageIdentity(referencedBy: package),
                    registry: &registry.known,
                    availablePackages: availablePackages
                ) {
                    // This is an invalid manifest condition diagnosed later. (No such package.)
                    // Treating it as unknown gracefully allows resolution to continue for now.
                    registry.unknown.insert(product)
                }
            } else { // < 5.2
                registry.unknown.insert(product)
            }
        case .byName(let product, _):
            if self.toolsVersion < .v5_2 {
                // A by‐name entry might be a product from anywhere.
                if self.targets.contains(where: { $0.name == product }) {
                    // Save the resolver some effort if it is known to only be a target anyway.
                    break
                } else {
                    registry.unknown.insert(product)
                }
            } else { // ≥ 5.2
                // If a by‐name entry is a product, it must be in a package of the same name.
                if !self.register(
                    product: product,
                    inPackage: self.packageIdentity(referencedBy: product),
                    registry: &registry.known,
                    availablePackages: availablePackages
                ) {
                    // If it doesn’t match a package, it should be a target, not a product.
                    if self.targets.contains(where: { $0.name == product }) {
                        break
                    } else {
                        // But in case the user is trying to reference a product,
                        // we still need to pass on the invalid reference
                        // so that the resolver fetches all dependencies
                        // in order to provide the diagnostic pass with the information it needs.
                        registry.unknown.insert(product)
                    }
                }
            }
        }
    }

    /// Registers a required plug‐in with a particular dependency if possible, or registers it as unknown.
    ///
    /// - Parameters:
    ///   - requiredPlugIn: The plug‐in to register.
    ///   - registry: The registry in which to record the association.
    ///   - availablePackages: The set of available packages.
    private func register(
        requiredPlugIn: TargetDescription.PluginUsage,
        registry: inout (known: [PackageIdentity: ProductFilter], unknown: Set<String>),
        availablePackages: Set<PackageIdentity>
    ) {
        switch requiredPlugIn {
        case .plugin(let name, let package):
            if let package {
                if !self.register(
                    product: name,
                    inPackage: self.packageIdentity(referencedBy: package),
                    registry: &registry.known,
                    availablePackages: availablePackages
                ) {
                    // Invalid, diagnosed later; see the dependency version of this method.
                    registry.unknown.insert(name)
                }
            } else {
                // The plug‐in is in the same package.
                break
            }
        }
    }

    /// Registers a required product with a particular dependency if possible.
    ///
    /// - Parameters:
    ///   - product: The product to try registering.
    ///   - package: The package to try associating it with.
    ///   - registry: The registry in which to record the association.
    ///   - availablePackages: The set of available packages.
    ///
    /// - Returns: `true` if the particular dependency was found and the product was registered; `false` if no matching
    /// dependency was found and the product has not yet been handled.
    private func register(
        product: String,
        inPackage package: PackageIdentity,
        registry: inout [PackageIdentity: ProductFilter],
        availablePackages: Set<PackageIdentity>
    ) -> Bool {
        if let existing = registry[package] {
            registry[package] = existing.union(.specific([product]))
            return true
        } else if availablePackages.contains(package) {
            registry[package] = .specific([product])
            return true
        } else {
            return false
        }
    }

    /// Returns a list of target descriptions whose root source directory is the same as that for the given type.
    public func targetsWithCommonSourceRoot(type: TargetDescription.TargetKind) -> [TargetDescription] {
        switch type {
        case .test:
            return self.targets.filter { $0.type == .test }
        case .plugin:
            return self.targets.filter { $0.type == .plugin }
        default:
            return self.targets.filter { $0.type != .test && $0.type != .plugin }
        }
    }

    /// Returns true if the tools version is >= 5.9 and the number of targets with a common source root is 1.
    public func shouldSuggestRelaxedSourceDir(type: TargetDescription.TargetKind) -> Bool {
        guard self.toolsVersion >= .v5_9 else {
            return false
        }
        return self.targetsWithCommonSourceRoot(type: type).count == 1
    }
}

extension Manifest: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Manifest, rhs: Manifest) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension Manifest: CustomStringConvertible {
    public var description: String {
        "<Manifest: \(self.displayName)>"
    }
}

extension Manifest: Encodable {
    private enum CodingKeys: CodingKey {
        case name, path, url, version, targetMap, toolsVersion,
             pkgConfig, providers, cLanguageStandard, cxxLanguageStandard, swiftLanguageVersions,
             dependencies, products, targets, traits, platforms, packageKind, revision,
             defaultLocalization
    }

    /// Coding user info key for dump-package command.
    ///
    /// Presence of this key will hide some keys when encoding the Manifest object.
    public static let dumpPackageKey: CodingUserInfoKey = .init(rawValue: "dumpPackage")!

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.displayName, forKey: .name)

        // Hide the keys that users shouldn't see when
        // we're encoding for the dump-package command.
        if encoder.userInfo[Manifest.dumpPackageKey] == nil {
            try container.encode(self.path, forKey: .path)
            try container.encode(self.packageLocation, forKey: .url)
            try container.encode(self.version, forKey: .version)
            try container.encode(self.targetMap, forKey: .targetMap)
        }

        try container.encode(self.toolsVersion, forKey: .toolsVersion)
        try container.encode(self.pkgConfig, forKey: .pkgConfig)
        try container.encode(self.providers, forKey: .providers)
        try container.encode(self.cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(self.cxxLanguageStandard, forKey: .cxxLanguageStandard)
        try container.encode(self.swiftLanguageVersions, forKey: .swiftLanguageVersions)
        try container.encode(self.dependencies, forKey: .dependencies)
        try container.encode(self.products, forKey: .products)
        try container.encode(self.targets, forKey: .targets)
        try container.encode(self.traits, forKey: .traits)
        try container.encode(self.platforms, forKey: .platforms)
        try container.encode(self.packageKind, forKey: .packageKind)
    }
}

/// Helper methods that enable data collection through traits configurations in manifests.
extension Manifest {
    /// The default traits as defined in this package as the root.
    public var defaultTraits: Set<TraitDescription> {
        traits.filter(\.isDefault)
    }

    /// A map of trait names to the trait description.
    public var traitsMap: [String: TraitDescription] {
        traits.reduce(into: [String: TraitDescription]()) { traitsMap, trait in
            traitsMap[trait.name] = trait
        }
    }

    // TODO: temporary workaround struct, to remove
    public struct TraitConfiguration: Codable, Hashable {
        /// The traits to enable for the package.
        package var enabledTraits: Set<String>?

        /// Enables all traits of the package.
        package var enableAllTraits: Bool

        package init(
            enabledTraits: Set<String>? = nil,
            enableAllTraits: Bool = false
        ) {
            self.enabledTraits = enabledTraits
            self.enableAllTraits = enableAllTraits
        }
    }


    public func enabledTraits(_ traitConfiguration: TraitConfiguration? = nil) -> Set<String> {
        guard let traitConfiguration else {
            return Set(defaultTraits.map(\.name))
        }

        var enabledTraits = traitConfiguration.enabledTraits ?? []

        if traitConfiguration.enableAllTraits {
            enabledTraits = Set(traits.map(\.name))
        }

        return enabledTraits
    }

    /// Given a trait, determine if the trait is enabled given the current trait configuration.
    public func isTraitEnabled(_ trait: TraitDescription, _ traitConfiguration: TraitConfiguration?) throws -> Bool {
        let allEnabledTraits = try calculateAllEnabledTraits(explictlyEnabledTraits: enabledTraits(traitConfiguration))

        return allEnabledTraits.contains(trait.name)
    }

    /// Calculates and returns a set of all enabled traits, beginning with a set of explicitly enabled traits (either defined by default traits of
    /// this manifest, or by a user-generated traits configuration) and determines which traits are transitively enabled.
    public func calculateAllEnabledTraits(explictlyEnabledTraits: Set<String>?) throws -> Set<String> {
        // This the point where we flatten the enabled traits and resolve the recursive traits
        var enabledTraits = explictlyEnabledTraits ?? []

        // We have to enable all default traits if no traits are enabled or the defaults are explicitly enabled
        let defaultTraits = self.defaultTraits
        if explictlyEnabledTraits == nil || !defaultTraits.isEmpty {
            enabledTraits.formUnion(defaultTraits.flatMap(\.enabledTraits))
        }

        // Iteratively flatten transitively enabled traits; stop when all transitive traits have been found.
        while true {
            let transitivelyEnabledTraits = Set(
                // We are going to calculate which traits are actually enabled for a node here. To do this
                // we have to check if default traits should be used and then flatten all the enabled traits.
                try enabledTraits
                    .flatMap { trait in
                        guard let traitDescription = traitsMap[trait] else {
                            // TODO: replace displayName with package identity.
                            throw InternalError("Trait '\(trait)' is not declared by package '\(self.displayName)'")
                        }
                        return traitDescription.enabledTraits
                    }
            )

            let appendedList = enabledTraits.union(transitivelyEnabledTraits)
            if appendedList.count == enabledTraits.count {
                break
            } else {
                enabledTraits = appendedList
            }
        }

        return enabledTraits
    }

    // TODO: consider traits flag to modify calculation
    public func usedDependencies(_ keepTraitGuardedDeps: Bool = true) throws -> [String: Set<TargetDescription.Dependency>] {
        try self.targets.reduce(into: [String: Set<TargetDescription.Dependency>]()) { depMap, target in
            let nonTraitDeps = target.dependencies.filter {
                $0.condition?.traits?.isEmpty ?? true
            }

            let traitGuardedDeps = try target.dependencies.filter { dep in
                let traits = dep.condition?.traits ?? []

                let package = self.packageDependency(referencedBy: dep)?.identity.description
                return try traits.allSatisfy({ try isTraitEnabled(.init(stringLiteral: $0), nil) })
            }

            let deps = nonTraitDeps + traitGuardedDeps
            depMap[target.name] = Set(deps)
        }
    }

    /// Returns the set of dependencies that are guarded by traits. This does not calculate enabled and disabled dependencies
    /// enforced by traits.
    public func traitGuardedDependencies() -> [String: Set<String>] {
        self.targets.reduce(into: [String: Set<String>]()) { depMap, target in
            let traitGuardedTargetDependencies = target.dependencies.filter({
                !($0.condition?.traits?.isEmpty ?? true)
            })
            traitGuardedTargetDependencies.forEach {
                guard let package = $0.package else { return }
                depMap[package, default: []].formUnion($0.condition?.traits ?? [])
            }
        }
    }

    /// Computes the trait configuration for a given target dependency
    public func traitConfiguration(forDependency dependency: TargetDescription.Dependency) -> TraitConfiguration? {
        guard let package = self.packageDependency(referencedBy: dependency),
              let traits = package.traits?.compactMap(\.name)
        else {
            return nil
        }

        return TraitConfiguration(enabledTraits: Set(traits))
    }

    public func isTargetDependencyEnabled(_ dependency: TargetDescription.Dependency) -> Bool {
        guard let package = dependency.package else { return false }
        let traitsThatEnableDependency = traitGuardedDependencies()[package] ?? []

        do {
            let isEnabled = try traitsThatEnableDependency.allSatisfy({ try isTraitEnabled(.init(stringLiteral: $0), nil) })

            return traitsThatEnableDependency.isEmpty || isEnabled
        } catch {
            // TODO: handle error
            return false
        }
    }

}
