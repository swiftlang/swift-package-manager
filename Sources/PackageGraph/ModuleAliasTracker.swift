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

// MARK: - ModuleAliasTracker

struct ModuleAliasTracker {
    /// All module aliases in the package graph.
    public private(set) var moduleAliases: IdentifiableSet<ModuleAlias> = []

    /// Key: fully qualified name of a product (package id + product name)
    /// Value: list of modules that the product depends on
    fileprivate var productModules: IdentifiableSet<ProductModules> = []
    fileprivate var packageModules: [PackageIdentity: IdentifiableSet<ModuleInfo>] = [:]
    /// Reverse index: for a module (by package + name), every product that vends it —
    /// i.e. every product whose `intraPackageModules` includes it. Purely structural (built
    /// once alongside `productModules`, before any aliasing state exists), so `vendingProducts(for:)`
    /// can look this up directly instead of scanning every product in the package on every call.
    fileprivate var vendingProductsIndex: [PackageIdentity: [String: Set<String>]] = [:]

    /// Flag that tracks whether module aliasing is being used in the current package graph.
    public var moduleAliasingUsed: Bool = false

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
            var visited: Set<String> = []
            var allDependencies: Set<String> = []
            var queue = module.dependencies.compactMap(\.module)
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard visited.insert(current.name).inserted else { continue }
                allDependencies.insert(current.name)
                queue.append(contentsOf: current.dependencies.compactMap(\.module))
            }
            self.allModuleDependencies = allDependencies
        }
    }

    /// A model that stores all transitively available modules for a given product in the package graph.
    public struct ProductModules: Identifiable {
        /// The product identity.
        let productId: String
        /// The product name.
        let productName: String
        /// The product package.
        let package: PackageIdentity
        /// The directly dependent modules needed for the product.
        let directModules: Set<String>
        /// All transitively dependent modules within the same package.
        let intraPackageModules: IdentifiableSet<ReachableModule>
        /// All transitively dependent cross-package products.
        var crossPackageChildProducts: Set<String> = []
        /// All modules reachable by recursively following `crossPackageChildProducts`,
        /// i.e. each child product's own `intraPackageModules` plus its own
        /// cross-package closure. Not meant to be queried directly; use `reachableModulesByName`
        /// for lookups. Populated once every product in the graph is known; empty until then.
        var crossPackageReachableModules: [PackageIdentity: IdentifiableSet<ReachableModule>] = [:]
        /// The same modules as `crossPackageReachableModules`, grouped by literal module name
        /// instead of by package — the query-facing counterpart: lets a name-based lookup
        /// (e.g. "what's reachable named X") go straight to the relevant candidates instead
        /// of scanning every reachable module.
        var reachableModulesByName: [String: [ReachableModule]] = [:]
        /// All products that transitively depend on this one, i.e. the mirror image of
        /// `crossPackageReachableModules`. Populated by `computeAllDependentProducts()`
        /// once every product's `crossPackageChildProducts` is known; empty until then.
        var crossPackageDependentProducts: Set<String> = []

        public var id: String {
            self.productId
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
        ///   modules' own closures is exactly this product's full intra-package module set.
        public init(
            product: Product,
            package: PackageIdentity,
            packageModules: IdentifiableSet<ModuleInfo>
        ) {
            self.productId = product.identity
            self.productName = product.name
            self.package = package
            let modules = product.modules
            self.directModules = Set(modules.map(\.name))

            var allModules: IdentifiableSet<ReachableModule> = []
            for module in modules {
                guard let moduleInfo = packageModules[module.name] else { continue }
                allModules.insert(.init(moduleInfo: moduleInfo, distance: 0))
                for dependencyName in moduleInfo.allModuleDependencies {
                    if let dependencyInfo = packageModules[dependencyName] {
                        allModules.insert(.init(moduleInfo: dependencyInfo, distance: 0))
                    }
                }
            }

            self.intraPackageModules = allModules

            var childProducts: Set<String> = []
            for module in allModules.values {
                for dep in module.dependencies {
                    if case let .product(productRef, _) = dep {
                        childProducts.insert(productRef.identity)
                    }
                }
            }
            self.crossPackageChildProducts = childProducts
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
            let terminalAlias: String
            let originatingPackage: PackageIdentity
            let declaringModule: Module
            let isRootDeclaration: Bool
            let isSelfRename: Bool
        }
        /// The name for which a consuming module knows the aliased module to be named as.
        let canonicalModuleName: String
        /// The set of candidate aliases for this module.
        var candidates: Set<Candidate>
        /// The set of products that vend this module.
        let vendingProducts: Set<String>

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

    /// Computes a reverse-lookup of dependent products per product. Mirrors
    /// `computeAllReachableModules()`'s bottom-up memoization: each product's dependent
    /// set is resolved exactly once and reused when composing the sets of everything
    /// above it, rather than re-walked from scratch per product.
    private mutating func computeAllDependentProducts() {
        var parentProducts: [String: Set<String>] = [:]
        for product in self.productModules.values {
            for childId in product.crossPackageChildProducts {
                parentProducts[childId, default: []].insert(product.productId)
            }
        }

        var resolved: Set<String> = []
        var inProgress: Set<String> = []

        func resolve(for productId: String) -> Set<String> {
            if resolved.contains(productId) {
                return self.productModules[productId]?.crossPackageDependentProducts ?? []
            }
            guard inProgress.insert(productId).inserted else {
                // Cycle guard; contribute nothing further along this path.
                return []
            }
            defer { inProgress.remove(productId) }

            var dependents: Set<String> = []
            for parentId in parentProducts[productId] ?? [] {
                dependents.insert(parentId)
                dependents.formUnion(resolve(for: parentId))
            }

            self.productModules[productId]?.crossPackageDependentProducts = dependents
            resolved.insert(productId)
            return dependents
        }

        for product in self.productModules.values {
            _ = resolve(for: product.productId)
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
                result.insert(siblingModule) // mirror the parent-inserts-child step, for the top-level entry point
            }
        }

        return result
    }

    public init(packages: [Package], _ observabilityScope: ObservabilityScope) throws {
        // Build the product -> module map and each package's own intra-package modules.
        packages.forEach({ package in
            self.addProductAndPackageModules(package)
        })

        // Resolve every product's full reachable-modules closure (with hop distance).
        self.computeAllReachableModules()

        // Compute the reverse lookup: which products transitively depend on each product.
        self.computeAllDependentProducts()

        // Register every module alias declaration found across the package graph.
        try self.addAliases(packages)

        // Propagate aliases across the package graph, applying terminal aliases.
        let proposedAliases = self.proposeAliases(observabilityScope)
        self.disambiguateAndApplyAliases(with: proposedAliases, observabilityScope)
    }

    /// Computes, for every product, the full set of modules reachable through it — tagged
    /// with hop distance — by recursively following `crossPackageChildProducts`.
    private mutating func computeAllReachableModules() {
        var resolved: Set<String> = []
        var inProgress: Set<String> = []

        func resolve(for productId: String) -> [PackageIdentity: IdentifiableSet<ProductModules.ReachableModule>] {
            guard let product = self.productModules[productId] else { return [:] }
            if resolved.contains(product.productId) {
                return product.crossPackageReachableModules
            }
            guard inProgress.insert(productId).inserted else {
                // Cycle guard; contribute nothing further along this path.
                return [product.package: product.intraPackageModules]
            }
            defer { inProgress.remove(productId) }
            var reachable: [PackageIdentity: IdentifiableSet<ProductModules.ReachableModule>] = [product.package: product.intraPackageModules]
            for childId in product.crossPackageChildProducts {
                for (pkg, modules) in resolve(for: childId) {
                    for module in modules.values {
                        let hopped = ProductModules.ReachableModule(moduleInfo: module.moduleInfo, distance: module.distance + 1)
                        if let existing = reachable[pkg]?[hopped.id], existing.distance <= hopped.distance {
                            continue
                        }
                        reachable[pkg, default: []][hopped.id] = hopped
                    }
                }
            }

            self.productModules[productId]?.crossPackageReachableModules = reachable
            self.productModules[productId]?.reachableModulesByName = Dictionary(grouping: reachable.values.flatMap(\.values), by: \.name)
            resolved.insert(productId)
            return reachable
        }

        for product in self.productModules.values {
            _ = resolve(for: product.productId)
        }
    }

    /// Adds all the modules that make up each product for `package`.
    public mutating func addProductAndPackageModules(_ package: Package) {
        let packageModules = IdentifiableSet(package.modules.map { ModuleInfo(module: $0, package: package.identity) })
        self.packageModules[package.identity] = packageModules

        for product in package.products {
            // Don't redundantly populate the modules map if this product was already added.
            guard productModules[product.identity] == nil else { continue }
            let newProduct = ProductModules(
                product: product,
                package: package.identity,
                packageModules: packageModules
            )
            self.productModules[product.identity] = newProduct

            for reachable in newProduct.intraPackageModules.values {
                self.vendingProductsIndex[reachable.packageId, default: [:]][reachable.name, default: []].insert(product.identity)
            }
        }
    }

    /// The set of products (by identity) belonging to `moduleInfo`'s own package that
    /// deliver/vend it — i.e. every product whose `intraPackageModules` includes it.
    /// Purely structural, precomputed once in `addProductAndPackageModules` — a direct
    /// lookup rather than a filter over every product in the package.
    private func vendingProducts(for moduleInfo: ModuleInfo) -> Set<String> {
        self.vendingProductsIndex[moduleInfo.packageId]?[moduleInfo.id] ?? []
    }

    /// Resolves what `name` refers to, reachable through `product` — either a still-plain
    /// canonical module (its own name matches `name` and it hasn't been aliased by anything
    /// yet), or a module some prior alias already renamed to `name`. Ties are broken by
    /// proximity: the closest reachable match wins, using the distance `computeAllReachableModules()`
    /// already precomputed. A genuine tie at the same distance is left unresolved, same as
    /// the original ambiguity check.
    private func resolveModule(for name: String, reachableThrough product: ProductModules) -> (moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)? {
        var matchesAtDistance: [Int: [(moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)]] = [:]
        // Candidates already aliased under a *different* name, where this lookup is asking
        // for their original canonical name again — only relevant as a fallback, so a
        // genuine still-plain sibling (a different physical module sharing the same literal
        // name) is always preferred over flagging a conflicting re-declaration.
        var reclaimAtDistance: [Int: [(moduleInfo: ModuleInfo, originatingPackage: PackageIdentity)]] = [:]

        // Candidates whose own literal name is `name` — via the precomputed index instead of
        // scanning every reachable module. Already-aliased ones only count as a reclaim
        // fallback; still-plain ones are direct matches.
        for reachable in product.reachableModulesByName[name] ?? [] {
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
            guard let reachable = product.reachableModulesByName[moduleAlias.module.name]?
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

    func hasCompetingModuleName(_ proposedAlias: String, for module: ModuleInfo) -> Bool {
        // Amongst the products that vend this module, determine all the modules that are grouped
        // within that product (both intra- and cross-package). Check that there isn't already a module
        // that is already named proposedAlias.canonicalModuleName.
        let vendingProducts = self.vendingProducts(for: module)
        guard !vendingProducts.isEmpty else { return true }
        let products = vendingProducts.compactMap({ self.productModules[$0] })
        for product in products {
            for other in product.reachableModules(named: proposedAlias) {
                let id = ModuleAlias.ModuleAliasID(moduleName: proposedAlias, packageIdentity: other.packageId)
                if self.moduleAliases[id] == nil {
                    return true
                }
            }
        }

        return false
    }

    public mutating func addAliases(_ packages: [Package]) throws {
        // To track aliases that have not yet been resolved; this applies to aliases that
        // do not have an identifiable "chain" yet, i.e. we have no matching ModuleAlias object.
        var unresolvedAliases: IdentifiableSet<ModuleAlias.Alias> = []

        for pkg in packages {
            // First pass; detect all direct aliases. Delegate unresolveable aliases for second pass.
            let consumingPackage = pkg.identity
            for module in pkg.modules {
                for dep in module.dependencies {
                    // Detected independent of whether this specific reference resolves (e.g. package: nil,
                    // an implicit/by-name product reference) — downstream diagnostics (like the
                    // tools-version-too-old warning) need to know aliasing was attempted at all.
                    if case let .product(productRef, _) = dep, let aliases = productRef.moduleAliases, !aliases.isEmpty {
                        self.moduleAliasingUsed = true
                    }

                    if case let .product(productRef, _) = dep,
                       let productPkg = productRef.package,
                       let aliases = productRef.moduleAliases,
                       let modulesForProduct = self.productModules[productRef.identity]
                        {
                        try aliases.forEach({ alias in
                            let aliasInfo = ModuleAlias.Alias(
                                name: alias.value,
                                overridenName: alias.key,
                                product: productRef,
                                declaringPackage: consumingPackage,
                                declaringModule: module,
                                originatingPackage: .plain(productPkg)
                            )

                            // For aliases that are direct i.e. override the canonical name of a module,
                            // or that chain onto an already-introduced alias name reachable through this product.
                            if let (moduleInfo, originatingPackage) = self.resolveModule(for: alias.key, reachableThrough: modulesForProduct) {
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
                                        productRef,
                                        originatingPackage
                                    )
                                } else {
                                    // New alias; add to the dict.
                                    let vendingProducts = self.vendingProducts(for: moduleInfo)
                                    let newAlias = ModuleAlias(
                                        module: moduleInfo.module,
                                        products: vendingProducts,
                                        package: moduleAliasId.packageIdentity,
                                    )
                                    try newAlias.addAlias(
                                        aliasInfo.name,
                                        oldName: aliasInfo.overridenName,
                                        aliasInfo.declaringPackage,
                                        module,
                                        productRef,
                                        originatingPackage
                                    )
                                    self.moduleAliases.insert(newAlias)
                                }
                            } else {
                                // For aliases that are possibly chained, or still ambiguous at this point
                                // in package-processing order; add to unresolved. We will retry these on
                                // a second pass, once every package has registered its own direct aliases.
                                let (inserted, existing) = unresolvedAliases.insert(aliasInfo)
                                if !inserted && existing.name != aliasInfo.name {
                                    throw PackageGraphError.multipleModuleAliases(
                                        module: aliasInfo.overridenName,
                                        product: aliasInfo.product.name,
                                        package: productPkg,
                                        aliases: [existing.name, aliasInfo.name]
                                    )
                                }
                            }
                        })
                    }
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
            guard let rootProductModules = self.productModules[root.product.identity],
                  let (moduleInfo, originatingPackage) = self.resolveModule(for: root.overridenName, reachableThrough: rootProductModules) else {
                // Genuinely unresolvable (e.g. ambiguous even after every package registered its
                // own aliases) — this chain is silently dropped.
                continue
            }

            // Correct root's originatingPackage to the verified value resolveModule just determined,
            // rather than the naive `.plain(productPkg)` guess it was created with.
            var correctedChain = chain
            correctedChain[correctedChain.count - 1] = ModuleAlias.Alias(
                name: root.name,
                overridenName: root.overridenName,
                product: root.product,
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
                let vendingProducts = self.vendingProducts(for: moduleInfo)
                let newAlias = ModuleAlias(module: moduleInfo.module, products: vendingProducts, package: moduleInfo.packageId)
                for alias in correctedChain.reversed() {
                    try newAlias.addAlias(alias)
                }
                self.moduleAliases.insert(newAlias)
            }
        }
    }

    /// Determines whether the given alias requires an entry in the module aliases mapping for a module.
    func needsOwnKeyEntry(for link: ModuleAlias.Alias) -> Bool {
        guard let linkModuleInfo = self.packageModules[link.declaringPackage]?[link.declaringModule.name] else { return false }
        let vendingProducts = self.vendingProducts(for: linkModuleInfo)
        return vendingProducts.contains { productId in
            guard let product = self.productModules[productId],
                  let ownDistance = product.reachableModulesByName[link.overridenName]?
                      .first(where: { $0.packageId == link.originatingPackage })?.distance else { return false }
            return (product.reachableModulesByName[link.overridenName] ?? []).contains(where: {
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

        func propose(_ terminalAlias: ModuleAlias.Alias, overridenName: String, for module: ModuleInfo, vendingProducts: Set<String>, originatingPackage: PackageIdentity, isRootDeclaration: Bool, isSelfRename: Bool = false) {
            if proposedAliases[module, default: []][overridenName] != nil {
                proposedAliases[module, default: []][overridenName]?.candidates.insert(.init(terminalAlias: terminalAlias.name, originatingPackage: originatingPackage, declaringModule: terminalAlias.declaringModule, isRootDeclaration: isRootDeclaration, isSelfRename: isSelfRename))
            } else {
                let proposedAlias = ProposedAlias(
                    canonicalModuleName: overridenName, candidates: [.init(terminalAlias: terminalAlias.name, originatingPackage: originatingPackage, declaringModule: terminalAlias.declaringModule, isRootDeclaration: isRootDeclaration, isSelfRename: isSelfRename)], vendingProducts: vendingProducts
                )
                proposedAliases[module, default: []][overridenName] = proposedAlias
            }
        }

        for moduleAlias in self.moduleAliases {
            let chains = moduleAlias.applyChainedAliases(observabilityScope)

            guard let aliasedModule = self.aliasedModule(for: moduleAlias) else { continue }

            let affectedModules = dependentIntraPackageModules(aliasedModule)
            let affectedProducts = moduleAlias.vendingProducts
                .compactMap({ self.productModules[$0]?.crossPackageDependentProducts })
                .flatMap({ $0 })

            for chain in chains {
                let terminal = chain.terminalAlias // the final name that this module will be aliased to
                guard let root = chain.chain.first else { continue }
                let isRootDeclaration = root.declaringModule == terminal.declaringModule

                // Diagnostics
                if chain.chain.count > 1  {
                    for link in chain.chain {
                        observabilityScope.emit(info: "Module alias '\(link.name)' defined in package '\(link.declaringPackage)' for target '\(link.declaringModule.name)' in package/product '\(link.product.name)' is overridden by alias '\(terminal.name)'; if this override is not intended, remove '\(terminal.name)' from 'moduleAliases' in its manifest")
                    }
                }

                // Propose the alias for each affected intra-package module
                for affectedModule in affectedModules {
                    propose(
                        terminal,
                        overridenName: moduleAlias.module.name,
                        for: affectedModule,
                        vendingProducts: moduleAlias.vendingProducts,
                        originatingPackage: moduleAlias.package,
                        isRootDeclaration: isRootDeclaration,
                        isSelfRename: affectedModule == aliasedModule
                    )
                }

                // Propose the alias for each affected modules via cross-package products.
                for affectedProduct in affectedProducts {
                    guard let product = self.productModules[affectedProduct] else { continue }
                    for reachable in product.intraPackageModules where product.directlyVendsModule(reachable.moduleInfo) {
                        propose(
                            terminal,
                            overridenName: moduleAlias.module.name,
                            for: reachable.moduleInfo,
                            vendingProducts: moduleAlias.vendingProducts,
                            originatingPackage: moduleAlias.package,
                            isRootDeclaration: isRootDeclaration
                        )
                    }
                }

                // Track each link in the module alias chain.
                for link in chain.chain.dropLast() {
                    guard let linkModuleInfo = self.packageModules[link.declaringPackage]?[link.declaringModule.name] else { continue }
                    guard needsOwnKeyEntry(for: link) else { continue }
                    propose(
                        terminal,
                        overridenName: link.name,
                        for: linkModuleInfo,
                        vendingProducts: moduleAlias.vendingProducts,
                        originatingPackage: moduleAlias.package,
                        isRootDeclaration: isRootDeclaration
                    )
                }
            }
        }

        return proposedAliases
    }

    /// Amongst the aliases that have been proposed, determine which mappings should be stored in each module if applicable.
    private mutating func disambiguateAndApplyAliases(with proposedAliases: [ModuleInfo: IdentifiableSet<ProposedAlias>], _ observabilityScope: ObservabilityScope) {
        func closestCandidate(_ proposedAlias: ProposedAlias, for moduleInfo: ModuleInfo) -> ProposedAlias.Candidate? {
            let vendingProducts = self.vendingProducts(for: moduleInfo)
            let candidatePackages = Set(proposedAlias.candidates.map(\.originatingPackage))

            var bestDistance: [PackageIdentity: Int] = [:]
            for productId in vendingProducts {
                guard let product = self.productModules[productId] else { continue }
                for candidatePackage in candidatePackages {
                    guard let match = product.reachableModulesByName[proposedAlias.canonicalModuleName]?
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

        for (moduleInfo, proposedAliases) in proposedAliases {
            for rawProposal in proposedAliases {
                var proposal = rawProposal
                proposal.candidates = preferContinuedOverRoot(proposal.candidates)
                let winner: String?
                // If the module in question is the one being aliased, always add.
                if let selfRename = proposal.candidates.first(where: { $0.isSelfRename }) {
                    winner = selfRename.terminalAlias
                } else if hasCompetingModuleName(proposal.canonicalModuleName, for: moduleInfo) {
                    winner = nil
                } else {
                    let allSelfDeclared = proposal.candidates.filter { $0.declaringModule == moduleInfo.module }
                    if allSelfDeclared.count > 1 {
                        winner = nil
                    } else if let onlySelfDeclared = allSelfDeclared.first {
                        winner = onlySelfDeclared.isRootDeclaration
                            ? closestCandidate(proposal, for: moduleInfo)?.terminalAlias
                            : onlySelfDeclared.terminalAlias
                    } else {
                        winner = closestCandidate(proposal, for: moduleInfo)?.terminalAlias
                    }
                }
                // Apply the winner, if one was found.
                if let winner {
                    let module = moduleInfo.module
                    module.addModuleAlias(for: proposal.canonicalModuleName, as: winner)
                    if module.sources.containsNonSwiftFiles, let aliases = module.moduleAliases {
                        let aliasesMsg = aliases.map({ "'\($0.key)' as '\($0.value)'" }).joined(separator: ", ")
                        for product in proposal.vendingProducts {
                            guard let product = self.productModules[product] else { continue }
                            observabilityScope.emit(warning: "target '\(module.name)' for product '\(product.productName)' from package '\(moduleInfo.packageId)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols")
                        }
                    }
                }
            }
        }
        // Apply all aliases — this is what actually renames each canonical module and
        // updates every module's moduleAliases dict to its physically-compiled name.
        for moduleAlias in self.moduleAliases {
            moduleAlias.applyAlias()
        }

        // Diagnose unapplied aliases — a declared alias that never produced a terminal
        // means it never matched any actual dependency of the product it was declared on.
        for moduleAlias in self.moduleAliases where moduleAlias.terminalAliases.isEmpty {
            if let diagnosedAlias = moduleAlias.aliases.first(where: { $0.overridenName == moduleAlias.module.name }) {
                observabilityScope.emit(warning: "module alias for target '\(moduleAlias.module.name)', declared in package '\(diagnosedAlias.declaringPackage)', does not match any recursive target dependency of product '\(diagnosedAlias.product.name)' from package '\(moduleAlias.package.description)'")
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
        /// The product dependency being consumed by `declaringPackage` in which
        /// `overridenName` is exposed — either as a canonical module name (direct alias)
        /// or as a prior alias name (chained alias).
        let product: Module.ProductReference
        /// The package consuming the product dependency and declaring the alias.
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
    var vendingProducts: Set<String> = []
    let package: PackageIdentity
    /// Flat list of all aliases (chained, etc.) for this module.
    var aliases: IdentifiableSet<Alias> = []
    var reverseLookupAliases: [Alias.AliasId: [Alias.AliasId]] = [:]
    /// Represents all terminal aliases (i.e. the final overridden name for a module) in the package graph.
    /// It's possible that there are multiple terminal aliases for a singular module depending on whether the alias
    /// chains have diverged in the package graph.
    public private(set) var terminalAliases: [Alias] = []

    /// The ID of this ModuleAlias object, representing a given module and its origin package.
    public struct ModuleAliasID: Hashable {
        var moduleName: String
        var packageIdentity: PackageIdentity
    }

    public var id: ID {
        .init(moduleName: module.name, packageIdentity: package)
    }


    init(
        module: Module,
        products: Set<String>,
        package: PackageIdentity
    ) {
        self.module = module
        self.vendingProducts = products
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
            alias.product,
            alias.originatingPackage
        )
    }

    func addAlias(
        _ alias: String,
        oldName: String,
        _ consumingPackage: PackageIdentity,
        _ declaringModule: Module,
        _ productRef: Module.ProductReference,
        _ originatingPackage: PackageIdentity
    ) throws {
        // Create alias.
        let alias = Alias(
            name: alias,
            overridenName: oldName,
            product: productRef,
            declaringPackage: consumingPackage,
            declaringModule: declaringModule,
            originatingPackage: originatingPackage
        )

        guard self.aliases.insert(alias).inserted else { return }
        self.reverseLookupAliases[alias.reverseId, default: []].append(alias.id)

        // Multiple different names for the same overridden name/originating package is only
        // a genuine conflict when the SAME declaring package is responsible for more than one
        // of them.
        if let aliasIds = self.reverseLookupAliases[alias.reverseId], aliasIds.count > 1 {
            let declaringPackages = aliasIds.map(\.declaringPackage)
            if Set(declaringPackages).count < declaringPackages.count {
                throw PackageGraphError.multipleModuleAliases(
                    module: alias.overridenName,
                    product: productRef.name,
                    package: self.package.description,
                    aliases: aliasIds.map { $0.name }
                )
            }
        }
    }
}
