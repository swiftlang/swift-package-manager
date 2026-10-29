//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel
import Basics

import func TSCBasic.transitiveClosure

// MARK: - ModuleAliasTracker

struct ModuleAliasTracker {
    /// All module aliases in the package graph.
    public private(set) var moduleAliases: IdentifiableSet<ModuleAlias> = []

    /// Key: a public component (a product, or a target with public visibility)
    /// Value: the modules that the public component depends on
    fileprivate var publicComponentModules: IdentifiableSet<PublicComponentModules> = []
    fileprivate var packageModules: [PackageIdentity: IdentifiableSet<ModuleInfo>] = [:]
    /// Reverse index: for a module (by package + name), every public component that vends it —
    /// i.e. every public component whose `intraPackageModules` includes it. Purely structural (built
    /// once alongside `publicComponentModules`, before any aliasing state exists), so `publicComponents(for:)`
    /// can look this up directly instead of scanning every public component in the package on every call.
    fileprivate var publicComponentsIndex: [PackageIdentity: [String: Set<PublicComponent>]] = [:]

    /// Flag that tracks whether module aliasing is being used in the current package graph.
    public var moduleAliasingUsed: Bool = false

    /// A component of a package exposed to dependents, either a product or target with public visibility.
    public enum PublicComponent: Hashable, Sendable {
        case product(identity: String, name: String)
        case publicTarget(ModuleAlias.ModuleAliasID)

        public var name: String {
            switch self {
            case .product(_, let name):
                return name
            case .publicTarget(let id):
                return id.moduleName
            }
        }

        public var diagnosticDescription: String {
            switch self {
            case .product(_, let name):
                return "product '\(name)'"
            case .publicTarget(let id):
                return "target '\(id.moduleName)'"
            }
        }
    }

    /// A model that stores direct module dependencies and the associated product, if any.
    public struct ModuleInfo: Identifiable, Hashable {
        /// The represented module.
        let module: Module
        /// A module's .module-type dependencies, defined within the same package.
        let directModuleDependencies: Set<String>
        /// A module's transitive module dependencies, within the same package.
        let allModuleDependencies: Set<String>
        /// The package identity for which this module belongs to.
        let packageId: PackageIdentity

        public var id: String {
            return module.name
        }

        public init(module: Module, package: PackageIdentity) {
            self.module = module
            self.packageId = package
            self.directModuleDependencies = Set(module.dependencies.compactMap(\.module).map(\.name))

            // `.module`-type dependencies carry the actual `Module` reference, so the
            // transitive closure can be walked directly without consulting the
            // package's full module map.
            self.allModuleDependencies = Set(
                transitiveClosure([module]) { $0.dependencies.compactMap(\.module) }.map(\.name)
            )
        }
    }

    /// A model that stores all transitively available modules for a given public component in the package graph.
    public struct PublicComponentModules: Identifiable {
        /// The public component identity.
        let publicComponent: PublicComponent
        /// The public component package.
        let package: PackageIdentity
        /// The directly dependent modules needed for the public component.
        let directModules: Set<String>
        /// All transitively dependent modules within the same package.
        let intraPackageModules: IdentifiableSet<ReachableModule>
        /// All transitively dependent cross-package public components.
        var crossPackageChildPublicComponents: Set<PublicComponent> = []
        /// All modules reachable by recursively following `crossPackageChildPublicComponents`,
        /// i.e. each child public component's own `intraPackageModules` plus its own
        /// cross-package closure. Populated once every public component in the graph is known; empty until then.
        var crossPackageReachableModules: [PackageIdentity: IdentifiableSet<ReachableModule>] = [:]
        /// The same modules as `crossPackageReachableModules`, grouped by literal module name
        /// instead of by package.
        var reachableModulesByName: [String: [ReachableModule]] = [:]
        /// All public components that transitively depend on this one, i.e. the mirror image of
        /// `crossPackageReachableModules`. Populated by `computeAllDependentPublicComponents()`
        /// once every public component's `crossPackageChildPublicComponents` is known; empty until then.
        var crossPackageDependentPublicComponents: Set<PublicComponent> = []

        public var id: PublicComponent {
            self.publicComponent
        }

        public struct ReachableModule: Identifiable, Hashable {
            let moduleInfo: ModuleInfo
            let distance: Int
            public var id: String { moduleInfo.id }
            public var name: String { moduleInfo.module.name }
            public var packageId: PackageIdentity { moduleInfo.packageId }
            public var dependencies: [Module.Dependency] {
                moduleInfo.module.dependencies
            }
        }

        /// - Parameter packageModules: every module of `package`, keyed by name, with its
        ///   `allModuleDependencies` already computed. Each direct module's own transitive
        ///   closure is looked up here rather than re-walked, since the union of the direct
        ///   modules' own closures is exactly this public component's full intra-package module set.
        public init(
            publicComponent: PublicComponent,
            package: PackageIdentity,
            modules: [Module],
            packageModules: IdentifiableSet<ModuleInfo>
        ) {
            self.publicComponent = publicComponent
            self.package = package
            self.directModules = Set(modules.map(\.name))

            var allModules: IdentifiableSet<ReachableModule> = []
            for module in modules {
                guard let moduleInfo = packageModules[module.name] else { continue }
                allModules.insertIfAbsent(.init(moduleInfo: moduleInfo, distance: 0))
                for dependencyName in moduleInfo.allModuleDependencies {
                    if let dependencyInfo = packageModules[dependencyName] {
                        allModules.insertIfAbsent(.init(moduleInfo: dependencyInfo, distance: 0))
                    }
                }
            }

            self.intraPackageModules = allModules
        }

        public func directlyVendsModule(_ module: ModuleInfo) -> Bool {
            return self.directlyVendsModule(module.module.name)
        }

        public func directlyVendsModule(_ module: String) -> Bool {
            return self.directModules.contains(module)
        }

        public func reachableModules(named module: String) -> [ReachableModule] {
            self.reachableModulesByName[module] ?? []
        }
    }

    /// An intermediary model to represent the possible aliases that a module may store.
    struct ProposedAlias: Identifiable, Hashable {
        struct Candidate: Hashable {
            /// The final name of the aliased module, and where and by which module it was declared.
            let terminalAlias: ModuleAlias.Alias
            /// The aliased module that `terminalAlias` is the final name of.
            let aliasedModule: ModuleAlias.ID
            let isRootDeclaration: Bool
            let isSelfRename: Bool

            /// The package that defines the aliased module.
            var originatingPackage: PackageIdentity { self.aliasedModule.packageIdentity }
        }
        /// The name for which a consuming module knows the aliased module to be named as.
        let canonicalModuleName: String
        /// The set of candidate aliases for this module.
        var candidates: Set<Candidate>
        /// The set of public components that vend this module.
        let publicComponents: Set<PublicComponent>

        var id: String {
            canonicalModuleName
        }

        static func == (lhs: ProposedAlias, rhs: ProposedAlias) -> Bool {
            lhs.canonicalModuleName == rhs.canonicalModuleName && lhs.candidates == rhs.candidates
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(canonicalModuleName)
            hasher.combine(candidates)
        }
    }

    /// Computes a reverse-lookup of dependent public components per public component. Mirrors
    /// `computeAllReachableModules()`'s bottom-up memoization: each public component's dependent
    /// set is resolved exactly once and reused when composing the sets of everything
    /// above it, rather than re-walked from scratch per public component.
    private mutating func computeAllDependentPublicComponents() {
        var parentPublicComponents: [PublicComponent: Set<PublicComponent>] = [:]
        for publicComponent in self.publicComponentModules.values {
            for childId in publicComponent.crossPackageChildPublicComponents {
                parentPublicComponents[childId, default: []].insert(publicComponent.publicComponent)
            }
        }

        var resolved: Set<PublicComponent> = []
        var inProgress: Set<PublicComponent> = []

        func resolve(for publicComponentId: PublicComponent) -> Set<PublicComponent> {
            if resolved.contains(publicComponentId) {
                return self.publicComponentModules[publicComponentId]?.crossPackageDependentPublicComponents ?? []
            }
            guard inProgress.insert(publicComponentId).inserted else {
                // Cycle guard; contribute nothing further along this path.
                return []
            }
            defer { inProgress.remove(publicComponentId) }

            var dependents: Set<PublicComponent> = []
            for parentId in parentPublicComponents[publicComponentId] ?? [] {
                dependents.insert(parentId)
                dependents.formUnion(resolve(for: parentId))
            }

            self.publicComponentModules[publicComponentId]?.crossPackageDependentPublicComponents = dependents
            resolved.insert(publicComponentId)
            return dependents
        }

        for publicComponent in self.publicComponentModules.values {
            _ = resolve(for: publicComponent.publicComponent)
        }
    }

    private func dependentIntraPackageModules(_ aliasedModule: ModuleInfo) -> IdentifiableSet<ModuleInfo> {
        guard let packageModules = self.packageModules[aliasedModule.packageId] else { return [] }
        var result: IdentifiableSet<ModuleInfo> = [aliasedModule]
        var memo: [String: Set<ModuleInfo>] = [:]
        var inProgress: Set<String> = []

        func checkDirectModuleDependencies(_ module: ModuleInfo) -> Set<ModuleInfo> {
            if let cached = memo[module.id] { return cached }
            guard inProgress.insert(module.id).inserted else { return [] } // cycle guard

            var localResult: Set<ModuleInfo> = []
            for moduleDep in module.directModuleDependencies {
                if moduleDep == aliasedModule.module.name {
                    localResult.insert(module)
                } else if let transitiveModuleDependency = packageModules[moduleDep] {
                    var transitiveModules = checkDirectModuleDependencies(transitiveModuleDependency)
                    if !transitiveModules.isEmpty {
                        transitiveModules.insert(transitiveModuleDependency)
                        localResult.formUnion(transitiveModules)
                    }
                }
            }
            inProgress.remove(module.id)
            memo[module.id] = localResult
            return localResult
        }

        for siblingModule in packageModules {
            let reached = checkDirectModuleDependencies(siblingModule)
            if !reached.isEmpty {
                result.formUnion(reached)
                result.insertIfAbsent(siblingModule) // mirror the parent-inserts-child step, for the top-level entry point
            }
        }

        return result
    }

    public init(packages: [Package], _ observabilityScope: ObservabilityScope) throws {
        // Build the public component -> module map and each package's own intra-package modules.
        packages.forEach({ package in
            self.addPublicComponentAndPackageModules(package)
        })

        // Resolve the cross-package public components each public component depends on, now that every public component is known.
        self.computeAllChildPublicComponents()

        // Resolve every public component's full reachable-modules closure (with hop distance).
        self.computeAllReachableModules()

        // Compute the reverse lookup: which public components transitively depend on each public component.
        self.computeAllDependentPublicComponents()

        // Register every module alias declaration found across the package graph.
        try self.addAliases(packages, observabilityScope)

        // Propagate aliases across the package graph, applying terminal aliases.
        let proposedAliases = self.proposeAliases(observabilityScope)
        self.disambiguateAndApplyAliases(with: proposedAliases, observabilityScope)
    }

    /// The public component that a cross-package dependency refers to, if it is known.
    private func publicComponent(for dependency: Module.Dependency) -> PublicComponent? {
        switch dependency {
        case .module:
            return nil
        case .product(let productRef, _):
            let product = PublicComponent.product(identity: productRef.identity, name: productRef.name)
            if self.publicComponentModules[product] != nil {
                return product
            }
            guard let package = productRef.package else { return nil }
            let publicTarget = PublicComponent.publicTarget(.init(moduleName: productRef.name, packageIdentity: .plain(package)))
            return self.publicComponentModules[publicTarget] != nil ? publicTarget : nil
        case .externalModule(let moduleRef, _):
            let publicTarget = PublicComponent.publicTarget(.init(moduleName: moduleRef.name, packageIdentity: .plain(moduleRef.package)))
            return self.publicComponentModules[publicTarget] != nil ? publicTarget : nil
        }
    }

    private mutating func computeAllChildPublicComponents() {
        for publicComponent in self.publicComponentModules.values {
            var dependencyModules = publicComponent.intraPackageModules.values.map(\.moduleInfo)
            if case .publicTarget(let id) = publicComponent.publicComponent, let moduleInfo = self.packageModules[id.packageIdentity]?[id.moduleName] {
                dependencyModules.append(moduleInfo)
            }

            var childPublicComponents: Set<PublicComponent> = []
            for moduleInfo in dependencyModules {
                for dependency in moduleInfo.module.dependencies {
                    if let childPublicComponent = self.publicComponent(for: dependency) {
                        childPublicComponents.insert(childPublicComponent)
                    }
                }
            }
            self.publicComponentModules[publicComponent.publicComponent]?.crossPackageChildPublicComponents = childPublicComponents
        }
    }

    /// Computes, for every public component, the full set of modules reachable through it — tagged
    /// with hop distance — by recursively following `crossPackageChildPublicComponents`.
    private mutating func computeAllReachableModules() {
        var resolved: Set<PublicComponent> = []
        var inProgress: Set<PublicComponent> = []

        func resolve(for publicComponentId: PublicComponent) -> [PackageIdentity: IdentifiableSet<PublicComponentModules.ReachableModule>] {
            guard let publicComponent = self.publicComponentModules[publicComponentId] else { return [:] }
            if resolved.contains(publicComponent.publicComponent) {
                return publicComponent.crossPackageReachableModules
            }
            guard inProgress.insert(publicComponentId).inserted else {
                // Cycle guard; contribute nothing further along this path.
                return [publicComponent.package: publicComponent.intraPackageModules]
            }
            defer { inProgress.remove(publicComponentId) }
            var reachable: [PackageIdentity: IdentifiableSet<PublicComponentModules.ReachableModule>] = [publicComponent.package: publicComponent.intraPackageModules]
            for childId in publicComponent.crossPackageChildPublicComponents {
                for (pkg, modules) in resolve(for: childId) {
                    for module in modules.values {
                        let hopped = PublicComponentModules.ReachableModule(moduleInfo: module.moduleInfo, distance: module.distance + 1)
                        if let existing = reachable[pkg]?[hopped.id], existing.distance <= hopped.distance {
                            continue
                        }
                        reachable[pkg, default: []][hopped.id] = hopped
                    }
                }
            }

            self.publicComponentModules[publicComponentId]?.crossPackageReachableModules = reachable
            self.publicComponentModules[publicComponentId]?.reachableModulesByName = Dictionary(grouping: reachable.values.flatMap(\.values), by: \.name)
            resolved.insert(publicComponentId)
            return reachable
        }

        for publicComponent in self.publicComponentModules.values {
            _ = resolve(for: publicComponent.publicComponent)
        }
    }

    /// Adds all the modules that make up each public component (product, or target with public visibility) for `package`.
    public mutating func addPublicComponentAndPackageModules(_ package: Package) {
        let packageModules = IdentifiableSet(package.modules.map { ModuleInfo(module: $0, package: package.identity) })
        self.packageModules[package.identity] = packageModules

        var publicComponents: [(publicComponent: PublicComponent, modules: [Module])] = package.products.map { product in
            (.product(identity: product.identity, name: product.name), product.modules)
        }
        for module in package.modules where module.visibility == .public {
            let publicComponent = PublicComponent.publicTarget(.init(moduleName: module.name, packageIdentity: package.identity))
            if module.type.isLibraryAggregate {
                publicComponents.append((publicComponent, module.dependencies.compactMap(\.module)))
            } else {
                publicComponents.append((publicComponent, [module]))
            }
        }

        for (publicComponent, modules) in publicComponents {
            // Don't redundantly populate the modules map if this public component was already added.
            guard publicComponentModules[publicComponent] == nil else { continue }
            let newPublicComponent = PublicComponentModules(
                publicComponent: publicComponent,
                package: package.identity,
                modules: modules,
                packageModules: packageModules
            )
            self.publicComponentModules[publicComponent] = newPublicComponent

            for reachable in newPublicComponent.intraPackageModules.values {
                self.publicComponentsIndex[reachable.packageId, default: [:]][reachable.name, default: []].insert(publicComponent)
            }
        }
    }

    /// The set of public components belonging to `moduleInfo`'s own package that
    /// deliver/vend it — i.e. every public component whose `intraPackageModules` includes it.
    /// Purely structural, precomputed once in `addPublicComponentAndPackageModules` — a direct
    /// lookup rather than a filter over every public component in the package.
    private func publicComponents(for moduleInfo: ModuleInfo) -> Set<PublicComponent> {
        self.publicComponentsIndex[moduleInfo.packageId]?[moduleInfo.id] ?? []
    }

    /// Resolves what `name` refers to, reachable through `publicComponent` — either a still-plain
    /// canonical module (its own name matches `name` and it hasn't been aliased by anything
    /// yet), or a module some prior alias already renamed to `name`. Ties are broken by
    /// proximity: the closest reachable match wins, using the distance `computeAllReachableModules()`
    /// already precomputed. A genuine tie at the same distance is left unresolved, same as
    /// the original ambiguity check.
    private func resolveModule(for name: String, reachableThrough publicComponent: PublicComponentModules) -> (moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)? {
        var matchesAtDistance: [Int: [(moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)]] = [:]
        // Candidates already aliased under a *different* name, where this lookup is asking
        // for their original canonical name again — only relevant as a fallback, so a
        // genuine still-plain sibling (a different physical module sharing the same literal
        // name) is always preferred over flagging a conflicting re-declaration.
        var reclaimAtDistance: [Int: [(moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)]] = [:]

        // Candidates whose own literal name is `name` — via the precomputed index instead of
        // scanning every reachable module. Already-aliased ones only count as a reclaim
        // fallback; still-plain ones are direct matches. Aggregate library targets have no
        // sources, so there is no module to rename.
        for reachable in publicComponent.reachableModulesByName[name] ?? [] where !reachable.moduleInfo.module.type.isLibraryAggregate {
            let candidate = reachable.moduleInfo
            let id = ModuleAlias.ModuleAliasID(moduleName: candidate.module.name, packageIdentity: candidate.packageId)
            if self.moduleAliases[id] != nil {
                reclaimAtDistance[reachable.distance, default: []].append((candidate, candidate.packageId))
            } else {
                matchesAtDistance[reachable.distance, default: []].append((candidate, candidate.packageId))
            }
        }

        // Candidates already aliased under a *different* canonical name, whose alias chain
        // produced `name` as a result — a chain continuation. Scoped to existing aliases
        // (typically far fewer than the full reachable set, since aliasing is the exception)
        // rather than scanning every reachable module to check whether it's aliased.
        for moduleAlias in self.moduleAliases {
            guard let matched = moduleAlias.aliases.first(where: { $0.name == name }) else { continue }
            guard let reachable = publicComponent.reachableModulesByName[moduleAlias.module.name]?
                .first(where: { $0.packageId == moduleAlias.package }) else { continue }
            matchesAtDistance[reachable.distance, default: []].append((reachable.moduleInfo, matched.declaringPackage))
        }

        if let closest = matchesAtDistance.keys.min(), let matches = matchesAtDistance[closest], matches.count == 1 {
            return matches[0]
        }
        // Nothing still-plain or chain-continued matched; if the sole reachable module under
        // this name turns out to already be aliased to something else, surface it anyway so
        // ModuleAlias.addAlias's own conflict check can flag the re-declaration.
        if matchesAtDistance.isEmpty, let closest = reclaimAtDistance.keys.min(), let matches = reclaimAtDistance[closest], matches.count == 1 {
            return matches[0]
        }
        return nil
    }

    private func libraryAggregate(named name: String, reachableThrough publicComponent: PublicComponentModules) -> ModuleInfo? {
        if case .publicTarget(let id) = publicComponent.publicComponent, id.moduleName == name,
           let moduleInfo = self.packageModules[id.packageIdentity]?[name], moduleInfo.module.type.isLibraryAggregate {
            return moduleInfo
        }
        return publicComponent.reachableModules(named: name).first { $0.moduleInfo.module.type.isLibraryAggregate }?.moduleInfo
    }

    func hasCompetingModuleName(_ proposedAlias: String, for module: ModuleInfo) -> Bool {
        // Amongst the public components of this module, determine all the modules that are grouped
        // within that public component (both intra- and cross-package). Check that there isn't already a module
        // that is already named proposedAlias.canonicalModuleName.
        let publicComponents = self.publicComponents(for: module)
        guard !publicComponents.isEmpty else { return true }
        let publicComponentModules = publicComponents.compactMap({ self.publicComponentModules[$0] })
        for publicComponent in publicComponentModules {
            for other in publicComponent.reachableModules(named: proposedAlias) {
                let id = ModuleAlias.ModuleAliasID(moduleName: proposedAlias, packageIdentity: other.packageId)
                if self.moduleAliases[id] == nil {
                    return true
                }
            }
        }

        return false
    }

    public mutating func addAliases(_ packages: [Package], _ observabilityScope: ObservabilityScope) throws {
        // To track aliases that have not yet been resolved; this applies to aliases that
        // do not have an identifiable "chain" yet, i.e. we have no matching ModuleAlias object.
        var unresolvedAliases: IdentifiableSet<ModuleAlias.Alias> = []

        for pkg in packages {
            // First pass; detect all direct aliases. Delegate unresolveable aliases for second pass.
            let consumingPackage = pkg.identity
            for module in pkg.modules {
                for dep in module.dependencies {
                    let aliases: [String: String]
                    let referencedPackage: String
                    switch dep {
                    case .module:
                        continue
                    case .product(let productRef, _):
                        guard let productAliases = productRef.moduleAliases, !productAliases.isEmpty else { continue }
                        // Detected independent of whether this specific reference resolves (e.g. package: nil,
                        // an implicit/by-name product reference) — downstream diagnostics (like the
                        // tools-version-too-old warning) need to know aliasing was attempted at all.
                        self.moduleAliasingUsed = true
                        guard let productPkg = productRef.package else { continue }
                        aliases = productAliases
                        referencedPackage = productPkg
                    case .externalModule(let moduleRef, _):
                        guard let moduleAliases = moduleRef.moduleAliases, !moduleAliases.isEmpty else { continue }
                        self.moduleAliasingUsed = true
                        aliases = moduleAliases
                        referencedPackage = moduleRef.package
                    }

                    guard let publicComponent = self.publicComponent(for: dep), let modulesForPublicComponent = self.publicComponentModules[publicComponent] else {
                        continue
                    }

                    try aliases.forEach({ alias in
                        let aliasInfo = ModuleAlias.Alias(
                            name: alias.value,
                            overridenName: alias.key,
                            publicComponent: publicComponent,
                            declaringPackage: consumingPackage,
                            declaringModule: module,
                            originatingPackage: .plain(referencedPackage)
                        )

                        // For aliases that are direct i.e. override the canonical name of a module,
                        // or that chain onto an already-introduced alias name reachable through this public component.
                        if let (moduleInfo, originatingPackage) = self.resolveModule(for: alias.key, reachableThrough: modulesForPublicComponent) {
                            let moduleAliasId = ModuleAlias.ModuleAliasID(
                                moduleName: moduleInfo.module.name,
                                packageIdentity: moduleInfo.packageId
                            )
                            // Existing alias; add to alias chain.
                            if let existingAlias = self.moduleAliases[moduleAliasId] {
                                try existingAlias.addAlias(
                                    aliasInfo.name,
                                    oldName: aliasInfo.overridenName,
                                    consumingPackage,
                                    module,
                                    publicComponent,
                                    originatingPackage
                                )
                            } else {
                                // New alias; add to the dict.
                                let publicComponents = self.publicComponents(for: moduleInfo)
                                let newAlias = ModuleAlias(
                                    module: moduleInfo.module,
                                    publicComponents: publicComponents,
                                    package: moduleAliasId.packageIdentity,
                                )
                                try newAlias.addAlias(
                                    aliasInfo.name,
                                    oldName: aliasInfo.overridenName,
                                    aliasInfo.declaringPackage,
                                    module,
                                    publicComponent,
                                    originatingPackage
                                )
                                self.moduleAliases.insertIfAbsent(newAlias)
                            }
                        } else if let aggregate = self.libraryAggregate(named: alias.key, reachableThrough: modulesForPublicComponent) {
                            observabilityScope.emit(ModuleAliasDiagnostic.aliasedLibraryAggregate(
                                module: aggregate.module.name,
                                declaringPackage: consumingPackage,
                                package: aggregate.packageId
                            ))
                        } else {
                            // For aliases that are possibly chained, or still ambiguous at this point
                            // in package-processing order; add to unresolved. We will retry these on
                            // a second pass, once every package has registered its own direct aliases.
                            let (inserted, existing) = unresolvedAliases.insertIfAbsent(aliasInfo)
                            if !inserted && existing.name != aliasInfo.name {
                                throw PackageGraphError.multipleModuleAliases(
                                    module: aliasInfo.overridenName,
                                    publicComponent: aliasInfo.publicComponent.diagnosticDescription,
                                    package: referencedPackage,
                                    aliases: [existing.name, aliasInfo.name]
                                )
                            }
                        }
                    })
                }
            }
        }

        // Set of IDs that represent which alias ids are overridden by another alias.
        let reverseLookupUnresolvedAliases = Set(unresolvedAliases.map(\.reverseId))
        // Set of aliases that represent the last node in the alias chain.
        let unresolvedTerminalAliases = unresolvedAliases.filter({ !reverseLookupUnresolvedAliases.contains($0.id) })

        for terminalAlias in unresolvedTerminalAliases {
            var chain: [ModuleAlias.Alias] = []
            var current: ModuleAlias.Alias? = terminalAlias
            while let alias = current {
                chain.append(alias)
                current = unresolvedAliases[alias.reverseId]
            }

            // The root represents the alias closest to the declaration of the canonical module name
            // wrt the alias chain (if any). Retry the same resolution the first pass tried — by now
            // every package has registered its own direct aliases, regardless of which order they
            // were processed in, so whatever narrowed/disambiguated the target may now be available.
            guard let root = chain.last else { continue }
            guard let rootPublicComponentModules = self.publicComponentModules[root.publicComponent],
                  let (moduleInfo, originatingPackage) = self.resolveModule(for: root.overridenName, reachableThrough: rootPublicComponentModules) else {
                // Genuinely unresolvable (e.g. ambiguous even after every package registered its
                // own aliases) — this chain is silently dropped.
                continue
            }

            // Correct root's originatingPackage to the verified value resolveModule just determined,
            // rather than the naive `.plain(referencedPackage)` guess it was created with.
            var correctedChain = chain
            correctedChain[correctedChain.count - 1] = ModuleAlias.Alias(
                name: root.name,
                overridenName: root.overridenName,
                publicComponent: root.publicComponent,
                declaringPackage: root.declaringPackage,
                declaringModule: root.declaringModule,
                originatingPackage: originatingPackage
            )

            let moduleAliasId = ModuleAlias.ModuleAliasID(moduleName: moduleInfo.module.name, packageIdentity: moduleInfo.packageId)
            if let existingAlias = self.moduleAliases[moduleAliasId] {
                for alias in correctedChain.reversed() {
                    try existingAlias.addAlias(alias)
                }
            } else {
                let publicComponents = self.publicComponents(for: moduleInfo)
                let newAlias = ModuleAlias(module: moduleInfo.module, publicComponents: publicComponents, package: moduleInfo.packageId)
                for alias in correctedChain.reversed() {
                    try newAlias.addAlias(alias)
                }
                self.moduleAliases.insertIfAbsent(newAlias)
            }
        }
    }

    /// Determines whether the given alias requires an entry in the module aliases mapping for a module.
    func needsOwnKeyEntry(for link: ModuleAlias.Alias) -> Bool {
        guard let linkModuleInfo = self.packageModules[link.declaringPackage]?[link.declaringModule.name] else { return false }
        let publicComponents = self.publicComponents(for: linkModuleInfo)
        return publicComponents.contains { publicComponentId in
            guard let publicComponent = self.publicComponentModules[publicComponentId],
                  let ownDistance = publicComponent.reachableModulesByName[link.overridenName]?
                      .first(where: { $0.packageId == link.originatingPackage })?.distance else { return false }
            return (publicComponent.reachableModulesByName[link.overridenName] ?? []).contains(where: {
                $0.packageId != link.originatingPackage && $0.distance <= ownDistance
            })
        }
    }

    private func aliasedModule(for moduleAlias: ModuleAlias) -> ModuleInfo? {
        self.packageModules[moduleAlias.package]?[moduleAlias.module.name]
    }

    /// Gather affected modules that depend (directly or transitively) on a module that is flagged to be aliased. Maintains a mapping of the modules that need to be aware
    /// of the incoming alias and the proposed aliases they must track.
    private mutating func proposeAliases(_ observabilityScope: ObservabilityScope) -> [ModuleInfo: IdentifiableSet<ProposedAlias>] {
        // Accumulate the proposed aliases to track in a given module.
        var proposedAliases: [ModuleInfo: IdentifiableSet<ProposedAlias>] = [:]

        func propose(
            _ chain: ModuleAlias.AliasChain,
            of moduleAlias: ModuleAlias,
            overridenName: String,
            for module: ModuleInfo,
            isSelfRename: Bool = false
        ) {
            // The final name that the aliased module will be known by
            let terminalAlias = chain.terminalAlias
            let candidate = ProposedAlias.Candidate(
                terminalAlias: terminalAlias,
                aliasedModule: moduleAlias.id,
                isRootDeclaration: chain.chain.first?.declaringModule == terminalAlias.declaringModule,
                isSelfRename: isSelfRename
            )
            if proposedAliases[module, default: []][overridenName] != nil {
                proposedAliases[module, default: []][overridenName]?.candidates.insert(candidate)
            } else {
                let proposedAlias = ProposedAlias(
                    canonicalModuleName: overridenName,
                    candidates: [candidate],
                    publicComponents: moduleAlias.publicComponents
                )
                proposedAliases[module, default: []][overridenName] = proposedAlias
            }
        }

        for moduleAlias in self.moduleAliases {
            let chains = moduleAlias.applyChainedAliases(observabilityScope)

            guard let aliasedModule = self.aliasedModule(for: moduleAlias) else { continue }

            let affectedModules = dependentIntraPackageModules(aliasedModule)
            let affectedPublicComponents = moduleAlias.publicComponents
                .compactMap({ self.publicComponentModules[$0]?.crossPackageDependentPublicComponents })
                .flatMap({ $0 })

            for chain in chains {
                let terminal = chain.terminalAlias // the final name that this module will be aliased to
                guard !chain.chain.isEmpty else { continue }

                // Diagnostics
                if chain.chain.count > 1  {
                    for link in chain.chain {
                        observabilityScope.emit(ModuleAliasDiagnostic.aliasOverridden(
                            alias: link.name,
                            declaringPackage: link.declaringPackage,
                            declaringModule: link.declaringModule.name,
                            publicComponent: link.publicComponent,
                            overriddenBy: terminal.name
                        ))
                    }
                }

                // Propose the alias for each affected intra-package module
                for affectedModule in affectedModules {
                    propose(chain, of: moduleAlias, overridenName: moduleAlias.module.name, for: affectedModule, isSelfRename: affectedModule == aliasedModule)
                }

                // Propose the alias for each affected modules via cross-package public components.
                for affectedPublicComponent in affectedPublicComponents {
                    guard let publicComponent = self.publicComponentModules[affectedPublicComponent] else { continue }
                    for reachable in publicComponent.intraPackageModules where publicComponent.directlyVendsModule(reachable.moduleInfo) {
                        propose(chain, of: moduleAlias, overridenName: moduleAlias.module.name, for: reachable.moduleInfo)
                    }
                }

                // Track each link in the module alias chain.
                for link in chain.chain.dropLast() {
                    guard let linkModuleInfo = self.packageModules[link.declaringPackage]?[link.declaringModule.name] else { continue }
                    guard needsOwnKeyEntry(for: link) else { continue }
                    propose(chain, of: moduleAlias, overridenName: link.name, for: linkModuleInfo)
                }
            }
        }

        return proposedAliases
    }

    /// The modules that `moduleInfo` directly depends on, which is a single hop: the modules of the public components that it (or
    /// the modules of its own package that it depends on) depends on, and the modules those directly depend on.
    private func directlyDependedOnModules(of moduleInfo: ModuleInfo) -> Set<ModuleAlias.ModuleAliasID> {
        var consumers: [Module] = [moduleInfo.module]
        let ownPackageModules = self.packageModules[moduleInfo.packageId]
        for name in moduleInfo.allModuleDependencies {
            if let module = ownPackageModules?[name]?.module {
                consumers.append(module)
            }
        }

        var dependencies: Set<ModuleAlias.ModuleAliasID> = []
        for consumer in consumers {
            for dependency in consumer.dependencies {
                guard let publicComponentId = self.publicComponent(for: dependency), let publicComponent = self.publicComponentModules[publicComponentId] else { continue }
                let publicComponentPackageModules = self.packageModules[publicComponent.package]
                for vendedName in publicComponent.directModules {
                    dependencies.insert(.init(moduleName: vendedName, packageIdentity: publicComponent.package))
                    guard let vended = publicComponentPackageModules?[vendedName] else { continue }
                    for dependencyName in vended.directModuleDependencies {
                        dependencies.insert(.init(moduleName: dependencyName, packageIdentity: publicComponent.package))
                    }
                }
            }
        }
        return dependencies
    }

    /// Amongst the aliases that have been proposed, determine which mappings should be stored in each module if applicable.
    private mutating func disambiguateAndApplyAliases(with proposedAliases: [ModuleInfo: IdentifiableSet<ProposedAlias>], _ observabilityScope: ObservabilityScope) {
        func closestCandidate(_ proposedAlias: ProposedAlias, for moduleInfo: ModuleInfo) -> ProposedAlias.Candidate? {
            let publicComponents = self.publicComponents(for: moduleInfo)
            let candidatePackages = Set(proposedAlias.candidates.map(\.originatingPackage))

            var bestDistance: [PackageIdentity: Int] = [:]
            for publicComponentId in publicComponents {
                guard let publicComponent = self.publicComponentModules[publicComponentId] else { continue }
                for candidatePackage in candidatePackages {
                    guard let match = publicComponent.reachableModulesByName[proposedAlias.canonicalModuleName]?
                        .first(where: { $0.packageId == candidatePackage }) else { continue }
                    if let existing = bestDistance[candidatePackage], existing <= match.distance { continue }
                    bestDistance[candidatePackage] = match.distance
                }
            }

            let minDistance = bestDistance.values.min()
            let closestCandidates = proposedAlias.candidates.filter { bestDistance[$0.originatingPackage] == minDistance }
            return closestCandidates.count == 1 ? closestCandidates.first : nil
        }

        // When a single canonical module's alias chain diverges into multiple terminal aliases
        // (e.g. two independent, unrelated paths through the graph each alias it differently),
        // every candidate that traces back to it shares the same originatingPackage. Prefer
        // whichever has been further chained/overridden downstream over a dead-end root
        // declaration for that same module — a root declaration that nobody built upon further
        // never had a chance to be superseded, so it shouldn't outrank one that did.
        func preferContinuedOverRoot(_ candidates: Set<ProposedAlias.Candidate>) -> Set<ProposedAlias.Candidate> {
            let grouped = Dictionary(grouping: candidates, by: \.originatingPackage)
            return Set(grouped.values.flatMap { group -> [ProposedAlias.Candidate] in
                guard group.count > 1 else { return group }
                let nonRoot = group.filter { !$0.isRootDeclaration }
                return nonRoot.isEmpty ? group : nonRoot
            })
        }

        // The winners to apply once every module has been decided: whether a module has to refer to an aliased module
        // directly depends on what the modules it depends on decided. `checkDependencies` is set for the winners that
        // were picked as the closest candidate, which are the ones that a dependency's direct reference overrides.
        var pending: [(moduleInfo: ModuleInfo, proposal: ProposedAlias, winner: String, checkDependencies: Bool)] = []
        var hasDirectReferences = false

        for (moduleInfo, proposedAliases) in proposedAliases {
            for rawProposal in proposedAliases {
                var proposal = rawProposal
                proposal.candidates = preferContinuedOverRoot(proposal.candidates)
                let winner: String?
                var checkDependencies = false
                // If the module in question is the one being aliased, always add.
                if let selfRename = proposal.candidates.first(where: { $0.isSelfRename }) {
                    winner = selfRename.terminalAlias.name
                } else if hasCompetingModuleName(proposal.canonicalModuleName, for: moduleInfo) {
                    winner = nil
                } else {
                    let allSelfDeclared = proposal.candidates.filter { $0.terminalAlias.declaringModule == moduleInfo.module }
                    if allSelfDeclared.count > 1 {
                        winner = nil
                    } else if let onlySelfDeclared = allSelfDeclared.first, !onlySelfDeclared.isRootDeclaration {
                        winner = onlySelfDeclared.terminalAlias.name
                    } else {
                        winner = closestCandidate(proposal, for: moduleInfo)?.terminalAlias.name
                        checkDependencies = true
                    }
                }

                if let winner {
                    pending.append((moduleInfo, proposal, winner, checkDependencies))
                } else {
                    // No alias could be picked, so this module refers to the aliased names directly. Record it on the
                    // aliased modules, so that the modules depending on this one can tell.
                    let aliasedNames = Set(rawProposal.candidates.map(\.terminalAlias.name)).sorted()
                    observabilityScope.emit(ModuleAliasDiagnostic.useAliasedNamesDirectly(
                        module: moduleInfo.module.name,
                        name: proposal.canonicalModuleName,
                        aliasedNames: aliasedNames
                    ))
                    let referencingModule = ModuleAlias.ModuleAliasID(moduleName: moduleInfo.module.name, packageIdentity: moduleInfo.packageId)
                    for candidate in proposal.candidates {
                        self.moduleAliases[candidate.aliasedModule]?.recordDirectReference(by: referencingModule, to: candidate.terminalAlias)
                        hasDirectReferences = true
                    }
                }
            }
        }

        // Apply the winners, unless a module that is directly depended on already refers to the aliased names directly.
        for (moduleInfo, proposal, winner, checkDependencies) in pending {
            if checkDependencies, hasDirectReferences {
                let dependencies = self.directlyDependedOnModules(of: moduleInfo)
                let mustReferDirectly = proposal.candidates.contains { candidate in
                    guard let moduleAlias = self.moduleAliases[candidate.aliasedModule] else {
                        return false
                    }
                    return moduleAlias.isReferencedDirectly(named: proposal.canonicalModuleName, by: dependencies)
                }
                if mustReferDirectly { continue }
            }
            let module = moduleInfo.module
            module.addModuleAlias(for: proposal.canonicalModuleName, as: winner)
        }

        // Warn about aliased modules that may contain non-Swift sources, once per public component that they belong to and with
        // their final aliases. A public component's modules are the ones that it vends and the ones those directly depend on.
        for publicComponent in self.publicComponentModules {
            let publicComponentPackageModules = self.packageModules[publicComponent.package]
            var moduleNames = publicComponent.directModules
            for name in publicComponent.directModules {
                moduleNames.formUnion(publicComponentPackageModules?[name]?.directModuleDependencies ?? [])
            }
            for name in moduleNames.sorted() {
                guard let module = publicComponentPackageModules?[name]?.module,
                      module.sources.containsNonSwiftFiles,
                      let aliases = module.moduleAliases else { continue }
                observabilityScope.emit(ModuleAliasDiagnostic.nonSwiftSources(
                    module: module.name,
                    publicComponent: publicComponent.publicComponent,
                    package: publicComponent.package,
                    aliases: aliases
                ))
            }
        }

        // Apply all aliases — this is what actually renames each canonical module and
        // updates every module's moduleAliases dict to its physically-compiled name.
        for moduleAlias in self.moduleAliases {
            moduleAlias.applyAlias()
        }

        // Diagnose unapplied aliases — a declared alias that never produced a terminal
        // means it never matched any actual dependency of the public component it was declared on.
        for moduleAlias in self.moduleAliases where moduleAlias.terminalAliases.isEmpty {
            if let diagnosedAlias = moduleAlias.aliases.first(where: { $0.overridenName == moduleAlias.module.name }) {
                observabilityScope.emit(ModuleAliasDiagnostic.unmatchedAlias(
                    module: moduleAlias.module.name,
                    declaringPackage: diagnosedAlias.declaringPackage,
                    publicComponent: diagnosedAlias.publicComponent,
                    package: moduleAlias.package
                ))
            }
        }
    }
}

// MARK: - ModuleAlias
public class ModuleAlias: Identifiable {
    public typealias ID = ModuleAliasID

    /// Representative of an instance of a declared module alias.
    /// A single module can have its aliases overridden
    public struct Alias: Identifiable {
        /// The new name in which the module is to be referred to.
        let name: String
        /// The module's old name.
        let overridenName: String
        /// The product or public target dependency being consumed by `declaringPackage` in which
        /// `overridenName` is exposed — either as a canonical module name (direct alias)
        /// or as a prior alias name (chained alias).
        let publicComponent: ModuleAliasTracker.PublicComponent
        /// The package consuming the dependency and declaring the alias.
        let declaringPackage: PackageIdentity
        /// The module declaring this module alias.
        let declaringModule: Module
        /// The package that defined the overriddenName of this alias.
        let originatingPackage: PackageIdentity

        public struct AliasId: Hashable {
            var name: String
            var declaringPackage: PackageIdentity
        }

        public var id: AliasId {
            .init(
                name: name,
                declaringPackage: declaringPackage
            )
        }

        public var reverseId: AliasId {
            .init(
                name: overridenName,
                declaringPackage: originatingPackage
            )
        }
    }

    var module: Module
    var publicComponents: Set<ModuleAliasTracker.PublicComponent> = []
    let package: PackageIdentity
    /// Flat list of all aliases (chained, etc.) for this module.
    var aliases: IdentifiableSet<Alias> = []
    var reverseLookupAliases: [Alias.AliasId: [Alias.AliasId]] = [:]
    /// Represents all terminal aliases (i.e. the final overridden name for a module) in the package graph.
    /// It's possible that there are multiple terminal aliases for a singular module depending on whether the alias
    /// chains have diverged in the package graph.
    public private(set) var terminalAliases: [Alias] = []

    /// A module that could not apply this module's alias as an entry, and so refers to the new name directly in source.
    struct DirectReference: Hashable {
        /// The module that refers to the aliased module by a new name.
        let referencingModule: ModuleAliasID
        /// The alias, i.e. the new name, that it refers to.
        let link: Alias
    }
    /// The modules that refer to this module by a new name directly.
    private(set) var directReferences: Set<DirectReference> = []

    func recordDirectReference(by module: ModuleAliasID, to link: Alias) {
        self.directReferences.insert(.init(referencingModule: module, link: link))
    }

    /// Whether one of `modules` refers to this module by a new name directly, with respect to `name`: either the
    /// name the module is known by (the one the alias replaces), or one of the new names that is referred to.
    func isReferencedDirectly<Modules: Collection>(named name: String, by modules: Modules) -> Bool where Modules.Element == ModuleAliasID {
        self.directReferences.contains { reference in
            modules.contains(reference.referencingModule)
                && (name == self.module.name || name == reference.link.name || name == reference.link.overridenName)
        }
    }

    /// The ID of any module, which is its name and the package that it belongs to. For a `ModuleAlias`, it identifies
    /// the module that it renames.
    public struct ModuleAliasID: Hashable, Sendable {
        var moduleName: String
        var packageIdentity: PackageIdentity
    }

    public var id: ID {
        .init(moduleName: module.name, packageIdentity: package)
    }


    init(
        module: Module,
        publicComponents: Set<ModuleAliasTracker.PublicComponent>,
        package: PackageIdentity
    ) {
        self.module = module
        self.publicComponents = publicComponents
        self.package = package
    }

    public struct AliasChain {
        var chain: [Alias]
        var terminalAlias: Alias
    }

    @discardableResult
    public func applyChainedAliases(_ observabilityScope: ObservabilityScope) -> [AliasChain] {
        let continuedIds = Set(self.aliases.map(\.reverseId))
        let terminalAliases = aliases.filter({ !continuedIds.contains($0.id) })
        self.terminalAliases = terminalAliases

        var results: [AliasChain] = []

        // Traverse the chain beginning with the terminal aliases.
        for terminalAlias in terminalAliases {
            var chain: [Alias] = []
            var current: Alias? = terminalAlias
            while let alias = current {
                chain.append(alias)
                current = self.aliases[alias.reverseId]
            }

            chain.reverse()
            results.append(.init(chain: chain, terminalAlias: terminalAlias))
        }

        return results
    }

    func applyAlias() {
        self.module.applyAlias()
    }

    func addAlias(_ alias: Alias) throws {
        try self.addAlias(
            alias.name,
            oldName: alias.overridenName,
            alias.declaringPackage,
            alias.declaringModule,
            alias.publicComponent,
            alias.originatingPackage
        )
    }

    func addAlias(
        _ alias: String,
        oldName: String,
        _ consumingPackage: PackageIdentity,
        _ declaringModule: Module,
        _ publicComponent: ModuleAliasTracker.PublicComponent,
        _ originatingPackage: PackageIdentity
    ) throws {
        // Create alias.
        let alias = Alias(
            name: alias,
            overridenName: oldName,
            publicComponent: publicComponent,
            declaringPackage: consumingPackage,
            declaringModule: declaringModule,
            originatingPackage: originatingPackage
        )

        guard self.aliases.insertIfAbsent(alias).inserted else { return }
        self.reverseLookupAliases[alias.reverseId, default: []].append(alias.id)

        // Multiple different names for the same overridden name/originating package is only
        // a genuine conflict when the SAME declaring package is responsible for more than one
        // of them.
        if let aliasIds = self.reverseLookupAliases[alias.reverseId], aliasIds.count > 1 {
            let declaringPackages = aliasIds.map(\.declaringPackage)
            if Set(declaringPackages).count < declaringPackages.count {
                throw PackageGraphError.multipleModuleAliases(
                    module: alias.overridenName,
                    publicComponent: publicComponent.diagnosticDescription,
                    package: self.package.description,
                    aliases: aliasIds.map { $0.name }
                )
            }
        }
    }
}

/// An alias is identified by its name and the package that declared it.
extension ModuleAlias.Alias: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
