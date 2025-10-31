//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

// MARK: - Traits Validation

/// Validator methods that check the correctness of traits and their support as defined in the manifest.
extension Manifest {
    /// Struct that contains information about a package's identity, as well as its name.
    public struct PackageIdentifier: Hashable, CustomStringConvertible {
        public var identity: String
        public var name: String?

        public init(identity: PackageIdentity, name: String? = nil) {
            self.init(identity: identity.description, name: name)
        }

        public init(identity: String, name: String? = nil) {
            self.identity = identity
            self.name = name
        }

        public init(_ parent: Manifest) {
            self.identity = parent.packageIdentity.description
            self.name = parent.displayName
        }

        public var description: String {
            var result = "'\(identity)'"
            if let name {
                result.append(" (\(name))")
            }
            return result
        }
    }

    /// Determines whether traits are supported for this Manifest.
    public var supportsTraits: Bool {
        !self.traits.isEmpty
    }

    /// Validates a trait by checking that it is defined in the manifest; if not, an error is thrown.
    private func validateTrait(_ trait: TraitDescription) throws {
        guard !trait.isDefault else {
            if !supportsTraits {
                throw TraitError.invalidTrait(
                    package: .init(self),
                    trait: .init(stringLiteral: trait.name),
                    availableTraits: traits.map({ $0.name })
                )
            }

            return
        }

        try self.validateTrait(EnabledTrait(stringLiteral: trait.name))
    }

    /// Validates a trait by checking that it is defined in the manifest; if not, an error is thrown.
    private func validateTrait(_ trait: EnabledTrait) throws {
        guard !trait.isDefault else {
            if !supportsTraits {
                throw TraitError.invalidTrait(
                    package: .init(self),
                    trait: trait,
                    availableTraits: traits.map({ $0.name })
                )
            }

            return
        }

        // Check if the passed trait is a valid trait.
        if self.traits.first(where: { $0.name == trait.name }) == nil {
            throw TraitError.invalidTrait(
                package: .init(self),
                trait: trait,
                availableTraits: self.traits.map({ $0.name })
            )
        }
    }

    /// Validates a set of traits that is intended to be enabled for the manifest; if there are any discrepencies in the
    /// set of enabled traits and whether the manifest defines these traits (or if it defines any traits at all), then an
    /// error indicating the issue will be thrown.
    private func validateEnabledTraits(_ explicitlyEnabledTraits: EnabledTraits) throws {
        guard supportsTraits else {
            if explicitlyEnabledTraits != ["default"] {
                throw TraitError.traitsNotSupported(
                    package: .init(self),
                    explicitlyEnabledTraits: explicitlyEnabledTraits.map({ $0 })
                )
            }

            return
        }

        let enabledTraits = explicitlyEnabledTraits

        // Validate each trait to assure it's defined in the current package.
        for trait in enabledTraits {
           try validateTrait(trait)
        }

        let areDefaultsEnabled = enabledTraits.contains("default")

        // Ensure that disabling default traits is disallowed for packages that don't define any traits.
        if !areDefaultsEnabled && !self.supportsTraits {
            // We throw an error when default traits are disabled for a package without any traits
            // This allows packages to initially move new API behind traits once.
            throw TraitError.traitsNotSupported(
                package: .init(self),
                explicitlyEnabledTraits: enabledTraits.map({ $0 })
            )
        }
    }

    private func validateTraitConfiguration(_ traitConfiguration: TraitConfiguration) throws {
        guard supportsTraits else {
            switch traitConfiguration {
            case .disableAllTraits:
                throw TraitError.traitsNotSupported(
                    package: .init(self),
                    explicitlyEnabledTraits: []
                )
            case .enabledTraits(let traits):
                throw TraitError.traitsNotSupported(
                    package: .init(self),
                    explicitlyEnabledTraits: traits.map({ .init(stringLiteral: $0) })
                )
            case .enableAllTraits, .default:
                return
            }
        }

        // Get the enabled traits; if the trait configuration's `.enabledTraits` returns nil,
        // we know that it's the `.enableAllTraits` case, since the config does not store
        // all the defined traits of the manifest itself.
        let enabledTraits: EnabledTraits = traitConfiguration.enabledTraits ?? EnabledTraits(self.traits.map(\.name), setBy: .traitConfiguration)

        try validateEnabledTraits(enabledTraits)
    }
}


// MARK: - Traits

/// Helper methods to calculate states of the manifest and its dependencies when given a set of enabled traits.
extension Manifest {
    /// The default traits as defined in this package as the root.
    public var defaultTraits: Set<String>? {
        // First, guard against whether this package actually has traits.
        guard self.supportsTraits else { return nil }
        return Set(self.traits.filter(\.isDefault).flatMap(\.enabledTraits))
    }

    /// A map of trait names to the trait description.
    public var traitsMap: [String: TraitDescription] {
        self.traits.reduce(into: [String: TraitDescription]()) { traitsMap, trait in
            traitsMap[trait.name] = trait
        }
    }

    /// Calculates the set of all transitive traits that are enabled for this manifest using the passed trait configuration.
    /// Since a trait configuration is only used for root packages, this method is intended for use with root packages only.
    public func enabledTraits(using traitConfiguration: TraitConfiguration) throws -> EnabledTraits {
        // If this manifest does not support traits, but the passed configuration either
        // disables default traits or enables non-default traits (i.e. traits that would
        // not exist for this manifest) then we must throw an error.
        try validateTraitConfiguration(traitConfiguration)
        guard supportsTraits, packageKind.isRoot else {
            return ["default"]
        }

        var enabledTraits: EnabledTraits = []

        switch traitConfiguration {
        case .enableAllTraits:
            enabledTraits = EnabledTraits(traits.map(\.name), setBy: .traitConfiguration)
        case .default:
            if let defaultTraits = defaultTraits {
                enabledTraits = EnabledTraits(defaultTraits, setBy: .default)
            }
        case .disableAllTraits:
            return []
        case .enabledTraits(let explicitlyEnabledTraits):
            enabledTraits = EnabledTraits(explicitlyEnabledTraits, setBy: .traitConfiguration)
        }

        if let allEnabledTraits = try? self.enabledTraits(using: enabledTraits) {
            enabledTraits = allEnabledTraits
        }

        return enabledTraits
    }

    /// Calculates the set of all transitive traits that are enabled for this manifest using the passed set of
    /// explicitly enabled traits, and the parent package that defines the enabled traits for this package.
    /// This method is intended for use with non-root packages.
    public func enabledTraits(using explicitlyEnabledTraits: EnabledTraits = ["default"]) throws -> EnabledTraits {
        // If this manifest does not support traits, but the passed configuration either
        // disables default traits or enables non-default traits (i.e. traits that would
        // not exist for this manifest) then we must throw an error.
        try validateEnabledTraits(explicitlyEnabledTraits)
        guard supportsTraits else {
            return ["default"]
        }

        var enabledTraits: EnabledTraits = []

        if let allEnabledTraits = try? calculateAllEnabledTraits(explicitlyEnabledTraits: explicitlyEnabledTraits) {
            enabledTraits = allEnabledTraits
        }

        return enabledTraits
    }

    /// Determines if a trait is enabled with a given set of enabled traits.
    public func isTraitEnabled(_ trait: TraitDescription, _ enabledTraits: EnabledTraits) throws -> Bool {
        // First, check that the queried trait is valid.
        try validateTrait(trait)
        // Then, check that the list of enabled traits is valid.
        try validateEnabledTraits(enabledTraits)

        // Special case for dealing with whether a default trait is enabled.
        guard !trait.isDefault else {
            // Check that the manifest defines default traits.
            if self.traits.contains(where: \.isDefault) {
                // If the trait is a default trait, then we must do the following checks:
                // - If there exists a list of enabled traits, ensure that the default trait
                //   is declared in the set.
                // - If there is no existing list of enabled traits (nil), and we know that the
                //   manifest has defined default traits, then just return true.
                // - If none of these conditions are met, then defaults aren't enabled and we return false.
                if enabledTraits.contains(trait.name) {
                    return true
                } else if enabledTraits.isEmpty {
                    return true
                } else {
                    return false
                }
            }

            // If manifest does not define default traits, then throw an invalid trait error.
            throw TraitError.invalidTrait(
                package: .init(self),
                trait: EnabledTrait(stringLiteral: trait.name),
                availableTraits: self.traits.map(\.name)
            )
        }

        guard supportsTraits else {
            // If the above checks pass without throwing an error, then we simply return false
            // if the manifest does not support traits.
            return false
        }

        // Compute all transitively enabled traits.
        let allEnabledTraits = try calculateAllEnabledTraits(explicitlyEnabledTraits: enabledTraits)

        return allEnabledTraits.contains(trait.name)
    }

    /// Calculates and returns a set of all enabled traits, beginning with a set of explicitly enabled traits (which can either be the default traits of a manifest, or a configuration of enabled traits determined from a user-generated trait configuration) and determines which traits are transitively enabled.
    private func calculateAllEnabledTraits(explicitlyEnabledTraits: EnabledTraits) throws -> EnabledTraits {
        try validateEnabledTraits(explicitlyEnabledTraits)
        // This the point where we flatten the enabled traits and resolve the recursive traits
        var enabledTraits = explicitlyEnabledTraits
        let areDefaultsEnabled = enabledTraits.remove("default") != nil

        // We have to enable all default traits if no traits are enabled or the defaults are explicitly enabled
        if explicitlyEnabledTraits == ["default"] || areDefaultsEnabled {
            if let defaultTraits {
                let transitiveDefaultTraits = EnabledTraits(
                    defaultTraits,
                    setBy: .default
                )
                enabledTraits.formUnion(transitiveDefaultTraits)
            }
        }

        // Initialize before loop to avoid recalculations of computed property
        let traitsMap = traitsMap

        // Iteratively flatten transitively enabled traits; stop when all transitive traits have been found.
        while true {
            // We are going to calculate which traits are actually enabled for a node here. To do this
            // we have to check if default traits should be used and then flatten all the enabled traits.
            let transitivelyEnabledTraits = try enabledTraits.flatMap { trait in
                guard let traitDescription = traitsMap[trait.name] else {
                    throw TraitError.invalidTrait(
                        package: .init(self),
                        trait: trait
                    )
                }
                return EnabledTraits(
                    traitDescription.enabledTraits,
                    setBy: .trait(traitDescription.name)
                )
            }


            let appendedList = enabledTraits.union(transitivelyEnabledTraits)
            if appendedList.count == enabledTraits.count {
                break
            } else {
                enabledTraits = appendedList
            }
        }

        return enabledTraits
    }

    /// Computes the dependencies that are in use per target in this manifest.
    public func usedTargetDependencies(withTraits enabledTraits: EnabledTraits) throws -> [String: Set<TargetDescription.Dependency>] {
        try self.targets.reduce(into: [String: Set<TargetDescription.Dependency>]()) { depMap, target in
            let nonTraitDeps = target.dependencies.filter {
                $0.condition?.traits?.isEmpty ?? true
            }

            let traitGuardedDeps = try target.dependencies.filter { dep in
                let traits = dep.condition?.traits ?? []

                // If traits is empty, then we must manually validate the explicitly enabled traits.
                if traits.isEmpty {
                    try validateEnabledTraits(enabledTraits)
                }
                // For each trait that is a condition on this target dependency, assure that
                // at least one is enabled in the manifest.
                return !traits.intersection(enabledTraits.names).isEmpty
            }

            let deps = nonTraitDeps + traitGuardedDeps
            depMap[target.name] = Set(deps)
        }
    }

    /// Computes the set of package dependencies that are used by targets of this manifest.
    public func usedDependencies(withTraits enabledTraits: EnabledTraits) throws -> (knownPackage: Set<String>, unknownPackage: Set<String>) {
        let deps = try self.usedTargetDependencies(withTraits: enabledTraits)
        .values
        .flatMap { $0 }
        .compactMap(\.package)

        var known: Set<String> = []
        var unknown: Set<String> = []

        for item in deps {
            if let dep = self.packageDependency(referencedBy: item) {
                known.insert(dep.identity.description)
            } else if self.targetMap[item] == nil {
                // Marking this dependency as tentatively used, given that we cannot find the package ref at this stage.
                unknown.insert(item)
            }
        }

        return (knownPackage: known, unknownPackage: unknown)
    }

    /// Computes the list of target dependencies per target that are guarded by traits.
    /// A target dependency is considered potentially trait-guarded if it defines a condition wherein there exists a
    /// list of traits.
    /// - Parameters:
    ///    - lowercasedKeys: A flag that determines whether the keys in the resulting dictionary are lowercased.
    /// - Returns: A dictionary that maps the name of a `TargetDescription` to a list of its dependencies that are
    /// guarded by traits.
    public func traitGuardedTargetDependencies(
        lowercasedKeys: Bool = false
    ) -> [String: [TargetDescription.Dependency]] {
        self.targets.reduce(into: [String: [TargetDescription.Dependency]]()) { depMap, target in
            let traitGuardedTargetDependencies = traitGuardedTargetDependencies(
                for: target
            )

            traitGuardedTargetDependencies.forEach {
                guard let package = lowercasedKeys ? $0.key.package?.lowercased() : $0.key.package else { return }
                depMap[package, default: []].append($0.key)
            }
        }
    }

    /// Computes the list of target dependencies that are guarded by traits for given target.
    /// A target dependency is considered potentially trait-guarded if it defines a condition wherein there exists a
    /// list of traits.
    /// - Parameters:
    ///    - target: A `TargetDescription` for which the trait-guarded target dependencies are calculated.
    /// - Returns: A dictionary that maps each trait-guarded `TargetDescription.Dependency` of the given
    /// `TargetDescription` to the list of traits that guard it.
    public func traitGuardedTargetDependencies(for target: TargetDescription)
        -> [TargetDescription.Dependency: Set<String>]
    {
        target.dependencies.filter {
            !($0.condition?.traits?.isEmpty ?? true)
        }.reduce(into: [TargetDescription.Dependency: Set<String>]()) { depMap, dep in
            depMap[dep, default: []].formUnion(dep.condition?.traits ?? [])
        }
    }

    /// Determines whether a target dependency is enabled given a set of enabled traits for this manifest.
    public func isTargetDependencyEnabled(
        target: String,
        _ dependency: TargetDescription.Dependency,
        enabledTraits: EnabledTraits,
    ) throws -> Bool {
        guard self.supportsTraits else { return true }
        guard let target = self.targetMap[target] else { return false }
        guard target.dependencies.contains(where: { $0 == dependency }) else {
            throw InternalError(
                "target dependency \(dependency.name) not found for target \(target.name) in package \(self.displayName)"
            )
        }

        let traitsToEnable = self.traitGuardedTargetDependencies(for: target)[dependency] ?? []

        // Check if any of the traits guarding this dependency is enabled;
        // if so, the condition is met and the target dependency is considered
        // to be in an enabled state.
        let isEnabled = try traitsToEnable.contains(where: { try self.isTraitEnabled(
            .init(stringLiteral: $0),
            enabledTraits,
        ) })

        return traitsToEnable.isEmpty || isEnabled
    }

    /// Determines whether a given package dependency is used by this manifest given a set of enabled traits.
    public func isPackageDependencyUsed(_ dependency: PackageDependency, enabledTraits: EnabledTraits) throws -> Bool {
        if self.pruneDependencies {
            let usedDependencies = try self.usedDependencies(withTraits: enabledTraits)
            let foundKnownPackage = usedDependencies.knownPackage.contains(where: {
                $0.caseInsensitiveCompare(dependency.identity.description) == .orderedSame
            })

            // if there is a target dependency referenced by name and the package it originates from is unknown, default to
            // tentatively marking the package dependency as used. to be resolved later on.
            return foundKnownPackage || (!foundKnownPackage && !usedDependencies.unknownPackage.isEmpty)
        } else {
            return try !isTraitGuarded(dependency, enabledTraits: enabledTraits)
        }
    }

    /// Given a set of enabled traits, determine whether a package dependecy of this manifest is
    /// guarded by traits.
    private func isTraitGuarded(_ dependency: PackageDependency, enabledTraits: EnabledTraits) throws -> Bool {
        try validateEnabledTraits(enabledTraits)

        let targetDependenciesForPackageDependency = self.targets.flatMap({ $0.dependencies })
            .filter({
            $0.package?.caseInsensitiveCompare(dependency.identity.description) == .orderedSame
        })

        let enabledTraitNames = enabledTraits.names

        // Determine whether the current set of enabled traits still gate the package dependency
        // across targets.
        let isTraitGuarded = targetDependenciesForPackageDependency.isEmpty ? false : targetDependenciesForPackageDependency.filter({ $0.condition?.traits != nil }).allSatisfy({ self.isTraitGuarded($0, enabledTraits: enabledTraits)
        })

        // Since we only omit a package dependency that is only guarded by traits, determine
        // whether this dependency is used elsewhere without traits.
        let isUsedWithoutTraitGuarding = !targetDependenciesForPackageDependency.filter({ $0.condition?.traits == nil }).isEmpty

        return !isUsedWithoutTraitGuarding && isTraitGuarded
    }

    private func isTraitGuarded(
        _ dependency: TargetDescription.Dependency,
        enabledTraits: EnabledTraits
    ) -> Bool {
        // Validate enabled traits
        guard let condition = dependency.condition, let traits = condition.traits else { return false }

        return enabledTraits.intersection(traits).isEmpty
    }
}

// MARK: - Trait Error

public enum TraitError: Swift.Error {
    /// Indicates that an invalid trait was enabled.
    case invalidTrait(
        package: Manifest.PackageIdentifier,
        trait: EnabledTrait,
        availableTraits: [String] = []
    )

    /// Indicates that the manifest does not support traits, yet a method was called with a configuration of enabled
    /// traits.
    case traitsNotSupported(
        package: Manifest.PackageIdentifier,
        explicitlyEnabledTraits: [EnabledTrait]
    )
}

extension TraitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidTrait(let package, let trait, var availableTraits):
            availableTraits = availableTraits.sorted()
            var errorMsg = "Trait '\(trait)'"
            let parentPackages = Set(trait.parentPackages)
            let parent: Manifest.PackageIdentifier? = parentPackages.count == 1 ? parentPackages.first : nil

            if let parent {
                errorMsg += " enabled by parent package \(parent)"
            }
            errorMsg += " is not declared by package \(package)."
            if availableTraits.isEmpty {
                errorMsg += " There are no available traits declared by this package."
            } else {
                errorMsg +=
                    " The available traits declared by this package are: \(availableTraits.joined(separator: ", "))."
            }
            return errorMsg
        case .traitsNotSupported(let package, var explicitlyEnabledTraits):
            explicitlyEnabledTraits = explicitlyEnabledTraits.sorted()
            let parentPackages = Set(explicitlyEnabledTraits.compactMap(\.parentPackages).flatMap({ $0 }))
            let parent: Manifest.PackageIdentifier? = parentPackages.count == 1 ? parentPackages.first : nil
            if explicitlyEnabledTraits.isEmpty {
                if let parent {
                    return """
            Disabled default traits by package \(parent) on package \(package) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.
            """
                } else {
                    return """
            Disabled default traits on package \(package) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.
            """
                }
            } else {
                if let parent {
                    return """
                Package \(parent) enables traits [\(explicitlyEnabledTraits.joined(separator: ", "))] on package \(package) that declares no traits.
                """
                } else {
                    return """
                Traits [\(explicitlyEnabledTraits.joined(separator: ", "))] have been enabled on package \(package) that declares no traits.
                """
                }
            }
        }
    }
}
