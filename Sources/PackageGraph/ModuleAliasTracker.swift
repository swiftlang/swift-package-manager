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

// This is a helper class that tracks module aliases in a package dependency graph
// and handles overriding upstream aliases where aliases themselves conflict.
struct ModuleAliasTracker {
    fileprivate var aliasMap = [String: [ModuleAliasModel]]()
    fileprivate var idToAliasMap = [PackageIdentity: [String: [ModuleAliasModel]]]()
    var idToProductToAllModules = [PackageIdentity: [String: [Module]]]()
    var productToDirectModules = [String: [Module]]()
    var productToAllModules = [String: [Module]]()
    var parentToChildProducts = [String: [String]]()
    var parentToChildIDs = [PackageIdentity: [PackageIdentity]]()
    var childToParentID = [PackageIdentity: PackageIdentity]()
    var appliedAliases = Set<String>()

    init() {}
    mutating func addModuleAliases(modules: [Module], package: PackageIdentity) throws {
        let moduleDependencies = modules.flatMap(\.dependencies)
        for dep in moduleDependencies {
            if case let .product(productRef, _) = dep,
               let productPkg = productRef.package {
                let productPkgID = PackageIdentity.plain(productPkg)
                // Track dependency package ID chain
                addPackageIDChain(parent: package, child: productPkgID)
                if let aliasList = productRef.moduleAliases {
                    // Track aliases for this product
                    try addAliases(aliasList,
                                   productID: productRef.identity,
                                   productName: productRef.name,
                                   originPackage: productPkgID,
                                   consumingPackage: package)
                }
            }
        }
    }

    mutating func addAliases(
        _ aliases: [String: String],
        productID: String,
        productName: String,
        originPackage: PackageIdentity,
        consumingPackage: PackageIdentity
    ) throws {
        if let aliasDict = idToAliasMap[originPackage] {
            let existingAliases = aliasDict.values.flatMap{$0}.filter { aliases.keys.contains($0.name) }
            for existingAlias in existingAliases {
                if let newAlias = aliases[existingAlias.name], newAlias != existingAlias.alias {
                    // Error if there are multiple different aliases specified for
                    // modules in this product
                    throw PackageGraphError.multipleModuleAliases(module: existingAlias.name, product: productName, package: originPackage.description, aliases: existingAliases.map{$0.alias} + [newAlias])
                }
            }
        }

        for (originalName, newName) in aliases {
            let model = ModuleAliasModel(name: originalName, alias: newName, originPackage: originPackage, consumingPackage: consumingPackage, productName: productName)
            idToAliasMap[originPackage, default: [:]][productID, default: []].append(model)
            aliasMap[productID, default: []].append(model)
        }
    }

    mutating func addPackageIDChain(parent: PackageIdentity, child: PackageIdentity) {
        if parentToChildIDs[parent]?.contains(child) ?? false {
            // Already added
        } else {
            parentToChildIDs[parent, default: []].append(child)
            // Used to track the top-most level package
            childToParentID[child] = parent
        }
    }

    // This func should be called once per product
    mutating func trackModulesPerProduct(product: Product, package: PackageIdentity) {
        let moduleDeps = product.modules.flatMap(\.dependencies)
        var allModuleDeps = product.modules.flatMap{$0.recursiveDependentModules.map{$0.dependencies}}.flatMap{$0}
        allModuleDeps.append(contentsOf: moduleDeps)
        for dep in allModuleDeps {
            if case let .product(depRef, _) = dep {
                parentToChildProducts[product.identity, default: []].append(depRef.identity)
            }
        }

        var allModulesInProduct = moduleDeps.compactMap(\.module)
        allModulesInProduct.append(contentsOf: product.modules)
        idToProductToAllModules[package, default: [:]][product.identity] = allModulesInProduct
        productToDirectModules[product.identity] = product.modules
        productToAllModules[product.identity] = allModulesInProduct
    }

    func validateAndApplyAliases(product: Product,
                                 package: PackageIdentity,
                                 observabilityScope: ObservabilityScope) throws {
        guard let modules = idToProductToAllModules[package]?[product.identity] else { return }
        let modulesWithAliases = modules.filter{ $0.moduleAliases != nil }
        for moduleWithAlias in modulesWithAliases {
            if moduleWithAlias.sources.containsNonSwiftFiles {
                let aliasesMsg = moduleWithAlias.moduleAliases?.map{"'\($0.key)' as '\($0.value)'"}.joined(separator: ", ") ?? ""
                observabilityScope.emit(warning: "target '\(moduleWithAlias.name)' for product '\(product.name)' from package '\(package.description)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols")
            }
            moduleWithAlias.applyAlias()
        }
    }

    mutating func propagateAliases(observabilityScope: ObservabilityScope) {
        // First get the root package ID
        var pkgID = childToParentID.first?.key
        var rootPkg = pkgID
        while pkgID != nil {
            rootPkg = pkgID
            // pkgID is not nil here so can be force unwrapped
            pkgID = childToParentID[pkgID!]
        }
        guard let rootPkg else { return }

        if let productToAllModules = idToProductToAllModules[rootPkg] {
            // First, propagate aliases upstream
            for productID in productToAllModules.keys {
                var aliasBuffer = [String: ModuleAliasModel]()
                propagate(productID: productID, observabilityScope: observabilityScope, aliasBuffer: &aliasBuffer)
            }

            // Then, merge or override upstream aliases downwards
            for productID in productToAllModules.keys {
                merge(productID: productID, observabilityScope: observabilityScope)
            }
        }
        // Finally, fill in aliases for modules in products that are in the
        // dependency chain but not in a product consumed by other packages
        fillInRest(package: rootPkg)
    }

    // Propagate defined aliases upstream. If they are chained, the final
    // alias value will be applied
    mutating private func propagate(
        productID: String,
        observabilityScope: ObservabilityScope,
        aliasBuffer: inout [String: ModuleAliasModel]
    ) {
        let productAliases = aliasMap[productID] ?? []
        for aliasModel in productAliases {
            // Alias buffer is used to carry down aliases defined upstream
            if let existing = aliasBuffer[aliasModel.name],
               existing.alias != aliasModel.alias {
                // check to allow only the most downstream alias is added
            } else {
                aliasBuffer[aliasModel.name] = aliasModel
            }
        }

        if let curDirectModules = productToDirectModules[productID] {
            var relevantModules = curDirectModules.map{$0.recursiveDependentModules}.flatMap{$0}
            relevantModules.append(contentsOf: curDirectModules)

            for relevantModule in relevantModules {
                if let val = lookupAlias(key: relevantModule.name, in: aliasBuffer) {
                    appliedAliases.insert(relevantModule.name)
                    relevantModule.addModuleAlias(for: relevantModule.name, as: val)
                    if let prechainVal = aliasBuffer[relevantModule.name],
                       prechainVal.alias != val {
                        relevantModule.addPrechainModuleAlias(for: relevantModule.name, as: prechainVal.alias)
                        appliedAliases.insert(prechainVal.alias)
                        relevantModule.addPrechainModuleAlias(for: prechainVal.alias, as: val)
                        observabilityScope.emit(info: "Module alias '\(prechainVal.alias)' defined in package '\(prechainVal.consumingPackage)' for target '\(relevantModule.name)' in package/product '\(productID)' is overridden by alias '\(val)'; if this override is not intended, remove '\(val)' from 'moduleAliases' in its manifest")
                        aliasBuffer.removeValue(forKey: prechainVal.alias)

                        // Since we're overriding an alias here, we have to pretend it was applied to avoid follow-on warnings.
                        var currentAlias: String? = val
                        while let _currentAlias = currentAlias, !appliedAliases.contains(_currentAlias) {
                            appliedAliases.insert(_currentAlias)
                            currentAlias = aliasBuffer.values.first { $0.alias == _currentAlias }?.name
                        }
                    }
                    aliasBuffer.removeValue(forKey: relevantModule.name)
                }
            }
        }

        guard let children = parentToChildProducts[productID] else {
            return
        }
        for childID in children {
            propagate(productID: childID,
                      observabilityScope: observabilityScope,
                      aliasBuffer: &aliasBuffer)
        }
    }

    // Merge all the upstream aliases and override them if necessary
    mutating func merge(productID: String, observabilityScope: ObservabilityScope) {
        guard let children = parentToChildProducts[productID] else {
            return
        }
        for childID in children {
            merge(productID: childID,
                  observabilityScope: observabilityScope)
        }

        if let curDirectModules = productToDirectModules[productID] {
            let depModules = curDirectModules.map{$0.recursiveDependentModules}.flatMap{$0}
            let depModuleAliases = toDictionary(depModules.compactMap{$0.moduleAliases})
            let depChildModules = dependencyProductModules(of: depModules)
            let depChildAliases = toDictionary(depChildModules.compactMap{$0.moduleAliases})
            let depChildPrechainAliases = toDictionary(depChildModules.compactMap{$0.prechainModuleAliases})
            chainModuleAliases(modules: depModules,
                               checkedModules: depModules,
                               moduleAliases: depModuleAliases,
                               childModules: depChildModules,
                               childAliases: depChildAliases,
                               childPrechainAliases: depChildPrechainAliases,
                               observabilityScope: observabilityScope)

            let relevantModules = depModules + curDirectModules
            let moduleAliases = toDictionary(relevantModules.compactMap{$0.moduleAliases})
            let depProductModules = dependencyProductModules(of: relevantModules)
            var depProductAliases = [String: [String]]()
            let depProductPrechainAliases = toDictionary(depProductModules.compactMap{$0.prechainModuleAliases})

            for depProdModule in depProductModules {
                let depProdModuleAliases = depProdModule.moduleAliases ?? [:]
                for (key, val) in depProdModuleAliases {
                    var shouldAddAliases = false
                    if depProdModule.name == key {
                        shouldAddAliases = true
                    } else if !depProductModules.map({$0.name}).contains(key) {
                        shouldAddAliases = true
                    }
                    if shouldAddAliases {
                        if depProductAliases[key]?.contains(val) ?? false {
                            // don't add a duplicate
                        } else {
                            depProductAliases[key, default: []].append(val)
                        }
                    }
                }
            }
            chainModuleAliases(modules: curDirectModules,
                               checkedModules: relevantModules,
                               moduleAliases: moduleAliases,
                               childModules: depProductModules,
                               childAliases: depProductAliases,
                               childPrechainAliases: depProductPrechainAliases,
                               observabilityScope: observabilityScope)
        }
    }

    // This fills in aliases for modules in products that are in the dependency
    // chain but not in a product consumed by other packages. Such modules still
    // need to have aliases applied to them so they can be built with correct
    // dependent binary names
    mutating func fillInRest(package: PackageIdentity) {
        if let productToModules = idToProductToAllModules[package] {
            for (_, productModules) in productToModules {
                let unAliased = productModules.contains { $0.moduleAliases == nil }
                if unAliased {
                    for module in productModules {
                        let depAliases = module.recursiveDependentModules.compactMap{$0.moduleAliases}.flatMap{$0}
                        for (key, alias) in depAliases {
                            appliedAliases.insert(key)
                            module.addModuleAlias(for: key, as: alias)
                        }
                    }
                }
            }
        }
        guard let children = parentToChildIDs[package] else { return }
        for child in children {
            fillInRest(package: child)
        }
    }

    func diagnoseUnappliedAliases(observabilityScope: ObservabilityScope) {
        for aliasList in aliasMap.values {
            for productAlias in aliasList {
                if !appliedAliases.contains(productAlias.name) {
                    observabilityScope.emit(warning: "module alias for target '\(productAlias.name)', declared in package '\(productAlias.consumingPackage)', does not match any recursive target dependency of product '\(productAlias.productName)' from package '\(productAlias.originPackage)'")
                }
            }
        }
    }

    private mutating func chainModuleAliases(
        modules: [Module],
        checkedModules: [Module],
        moduleAliases: [String: [String]],
        childModules: [Module],
        childAliases: [String: [String]],
        childPrechainAliases: [String: [String]],
        observabilityScope: ObservabilityScope
    ) {
        guard !modules.isEmpty else { return }
        var aliasDict = [String: String]()
        var prechainAliasDict = [String: [String]]()
        var directRefAliasDict = [String: [String]]()
        let childDirectRefAliases = toDictionary(childModules.compactMap{$0.directRefAliases})
        for (childModuleName, childModuleAliases) in childAliases {
            // Tracks whether to add prechain aliases to modules
            var addPrechainAliases = false
            // Current modules and their dependents contain this child product
            // module name
            if checkedModules.map(\.name).contains(childModuleName) {
                addPrechainAliases = true
            }
            if let overlappingModuleAliases = moduleAliases[childModuleName], !overlappingModuleAliases.isEmpty {
                // Current module aliases have the same key as this child
                // module name, so the child module alias should not be applied
                addPrechainAliases = true
                aliasDict[childModuleName] = overlappingModuleAliases.first
            } else if childModuleAliases.count > 1 {
                // Multiple aliases from different products for this child module
                // name exist so they should not be applied; their aliases / new
                // names should be used directly
                addPrechainAliases = true
            } else if childModules.filter({$0.name == childModuleName}).count > 1 {
                // Modules from different products have the same name as this child
                // module name, so their aliases should not be applied
                addPrechainAliases = true
            }

            if addPrechainAliases {
                if let prechainAliases = childPrechainAliases[childModuleName] {
                   for prechainAliasKey in prechainAliases {
                       if let prechainAliasVals = childPrechainAliases[prechainAliasKey] {
                           // If aliases are chained, keep track of prechain
                           // aliases
                           prechainAliasDict[prechainAliasKey, default: []].append(contentsOf: prechainAliasVals)
                           // Add prechained aliases to the list of aliases
                           // that should be directly referenced in source code
                           directRefAliasDict[childModuleName, default: []].append(prechainAliasKey)
                           directRefAliasDict[prechainAliasKey, default: []].append(contentsOf: prechainAliasVals)
                       }
                    }
                } else if aliasDict[childModuleName] == nil {
                    // If not added to aliasDict, use the renamed module directly
                    directRefAliasDict[childModuleName, default: []].append(contentsOf: childModuleAliases)
                }
            } else if let productModuleAlias = childModuleAliases.first {
                if childModuleAliases.count > 1 {
                    observabilityScope.emit(warning: "There should be one alias for target '\(childModuleName)' but there are [\(childModuleAliases.map{"'\($0)'"}.joined(separator: ", "))]")
                }
                // Check if not in child modules' direct ref aliases list, then add
                if lookupAlias(value: childModuleName, in: childDirectRefAliases).isEmpty,
                   childDirectRefAliases[childModuleName] == nil {
                    aliasDict[childModuleName] = productModuleAlias
                }
            }
        }

        for module in modules {
            for (key, val) in aliasDict {
                appliedAliases.insert(key)
                module.addModuleAlias(for: key, as: val)
            }
            for (key, valList) in prechainAliasDict {
                if let val = valList.first,
                    valList.count <= 1 {
                    appliedAliases.insert(key)
                    module.addModuleAlias(for: key, as: val)
                    module.addPrechainModuleAlias(for: key, as: val)
                }
            }
            for (key, list) in directRefAliasDict {
                module.addDirectRefAliases(for: key, as: list)
                observabilityScope.emit(info: "Target '\(module.name)' has a dependency on multiple targets named '\(key)'; the aliased names are [\(list.map{"'\($0)'"}.joined(separator: ", "))] and should be used directly in source code if referenced from '\(module.name)'")
            }
        }
    }

    private func lookupAlias(key: String, in buffer: [String: ModuleAliasModel]) -> String? {
        var next = key
        while let nextValue = buffer[next] {
            next = nextValue.alias
        }
        return next == key ? nil : next
    }

    private func lookupAlias(value: String, in dict: [String: [String]]) -> [String] {
        let keys = dict.filter{$0.value.contains(value)}.map{$0.key}
        return keys
    }

    private func toDictionary(_ list: [[String: [String]]]) -> [String: [String]] {
        var dict = [String: [String]]()
        for entry in list {
            for (entryKey, entryVal) in entry {
                dict[entryKey, default: []].append(contentsOf: entryVal)
            }
        }
        return dict
    }

    private func toDictionary(_ list: [[String: String]]) -> [String: [String]] {
        var dict = [String: [String]]()
        for entry in list {
            for (entryKey, entryVal) in entry {
                if let existing = dict[entryKey], existing.contains(entryVal) {
                    // don't add a duplicate
                } else {
                    dict[entryKey, default: []].append(entryVal)
                }
            }
        }
        return dict
    }

    private func dependencyProductModules(of modules: [Module]) -> [Module] {
        let result = modules.map{$0.dependencies.compactMap{$0.product?.identity}}.flatMap{$0}.compactMap{productToAllModules[$0]}.flatMap{$0}
        return result
    }
}

// Used to keep track of module alias info for each package
private class ModuleAliasModel {
    let name: String
    var alias: String
    let originPackage: PackageIdentity
    let consumingPackage: PackageIdentity
    let productName: String

    init(name: String, alias: String, originPackage: PackageIdentity, consumingPackage: PackageIdentity, productName: String) {
        self.name = name
        self.alias = alias
        self.originPackage = originPackage
        self.consumingPackage = consumingPackage
        self.productName = productName
    }
}

extension Module {
    func dependsOn(productID: String) -> Bool {
        return self.dependencies.contains { dep in
            if case let .product(prodRef, _) = dep {
                return prodRef.identity == productID
            }
            return false
        }
    }

    var recursiveDependentModules: [Module] {
        print("[ModuleAlias] BFS invoked on: \(self.name)")
        var list = [Module]()
        var nextDeps = self.dependencies
        while !nextDeps.isEmpty {
            let nextModules = nextDeps.compactMap{$0.module}
            nextModules.forEach { print("[ModuleAlias] visiting: \($0.name)") }
            list.append(contentsOf: nextModules)
            nextDeps = nextModules.map{$0.dependencies}.flatMap{$0}
        }
        return list
    }
}

// MARK: - ModuleAliasTracker

struct ModuleAliasTracker2 {
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
        /// cross-package closure. Keyed by package purely because that's what the
        /// memoized build in `computeAllReachableModules()` needs (an O(1) "is there
        /// already a closer entry" check while merging each child in) — not meant to be
        /// queried directly; use `reachableModulesByName` for lookups. Populated once every
        /// product in the graph is known; empty until then.
        var crossPackageReachableModules: [PackageIdentity: IdentifiableSet<ReachableModule>] = [:]
        /// The same modules as `crossPackageReachableModules`, grouped by literal module name
        /// instead of by package — the query-facing counterpart: lets a name-based lookup
        /// (e.g. "what's reachable named X") go straight to the relevant candidates instead
        /// of scanning every reachable module. Populated alongside `crossPackageReachableModules`;
        /// empty until then.
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
        self.applyAliases(observabilityScope)
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

    /// Propagates every module alias across the package graph and applies the terminal aliases.
    private mutating func applyAliases(_ observabilityScope: ObservabilityScope) {

        struct ProposedAlias: Identifiable, Hashable {
            struct Candidate: Hashable {
                let terminalAlias: String
                let originatingPackage: PackageIdentity
                let declaringModule: Module
                // True when this candidate's chain root and terminal share the same declarer —
                // i.e. the declaring module directly aliased the canonical name itself, rather
                // than relaying/continuing an alias that started elsewhere. A root declarer
                // already resolved its own literal name unambiguously by writing the alias;
                // it isn't a genuine downstream consumer of the broadcast.
                let isRootDeclaration: Bool
                // True when this candidate represents the canonical module renaming ITSELF
                // (moduleInfo IS the module the alias chain targets), rather than some other
                // consumer resolving what a literal import means. A module's own identity
                // change isn't ambiguous just because an unrelated same-named module happens
                // to also be reachable through it — that concerns other consumers deciding
                // what the literal name means to THEM, not this module's own rename.
                let isSelfRename: Bool
            }
            let canonicalModuleName: String
            var candidates: Set<Candidate>
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

        // Track the proposed aliases to track in a given module.
        var proposedAliases: [ModuleInfo: IdentifiableSet<ProposedAlias>] = [:]

        for moduleAlias in self.moduleAliases {
            let chains = moduleAlias.applyChainedAliases(observabilityScope)

            for chain in chains {
                guard let root = chain.chain.first else { continue }
                let terminal = chain.terminalAlias
                let isRootDeclaration = root.declaringModule == terminal.declaringModule

                // Diagnostics
                if chain.chain.count > 1  {
                    for link in chain.chain {
                        observabilityScope.emit(info: "Module alias '\(link.name)' defined in package '\(link.declaringPackage)' for target '\(link.declaringModule.name)' in package/product '\(link.product.name)' is overridden by alias '\(terminal.name)'; if this override is not intended, remove '\(terminal.name)' from 'moduleAliases' in its manifest")
                    }
                }

                // Track down what intra-package modules the aliased module will affect
                if let aliasedModuleInfo = self.packageModules[root.originatingPackage]?[root.overridenName] {
                    let affectedModules = dependentIntraPackageModules(aliasedModuleInfo)
                    for moduleInfo in affectedModules {
                        propose(
                            terminal,
                            overridenName: root.overridenName,
                            for: moduleInfo,
                            vendingProducts: moduleAlias.vendingProducts,
                            originatingPackage: moduleAlias.package,
                            isRootDeclaration: isRootDeclaration,
                            isSelfRename: moduleInfo == aliasedModuleInfo
                        )
                    }
                }

                // If the root's declaring module can also reach a *different* module (whether an
                // intra-package sibling or a cross-package dependency of its own) that also literally
                // matches root.overridenName at the same or closer distance than the canonical module
                // itself, that module's own source can't safely use the canonical name — it's a genuine
                // tie, not just something else incidentally reachable farther away (which closest-wins
                // logic elsewhere already resolves unambiguously). A real tie means it uses its own
                // chosen alias name instead, so it needs the further-downstream terminal value keyed
                // by THAT name rather than the canonical one. Also requires an actual chain beyond
                // root — if root is also the terminal, root.name == terminal.name and this would just
                // propose a no-op identity mapping onto the declaring module itself.
                if chain.chain.count > 1,
                   let rootModuleInfo = self.packageModules[root.declaringPackage]?[root.declaringModule.name] {
                    let vendingProducts = self.vendingProducts(for: rootModuleInfo)
                    let hasCompetingModule = vendingProducts.contains { productId in
                        guard let product = self.productModules[productId],
                              let canonicalDistance = product.reachableModulesByName[root.overridenName]?
                                  .first(where: { $0.packageId == root.originatingPackage })?.distance else { return false }
                        return (product.reachableModulesByName[root.overridenName] ?? []).contains(where: {
                            $0.packageId != root.originatingPackage && $0.distance <= canonicalDistance
                        })
                    }
                    if hasCompetingModule {
                        propose(
                            terminal,
                            overridenName: root.name,
                            for: rootModuleInfo,
                            vendingProducts: moduleAlias.vendingProducts,
                            originatingPackage: moduleAlias.package,
                            isRootDeclaration: isRootDeclaration
                        )
                    }
                }

                // Propose module alias for relevant modules; iterate through intermediate links in the alias chain
                // to determine the intermediary modules that require knowledge of the terminal alias name.
                for link in chain.chain {
                    let module = link.declaringModule
                    guard let productModules = productModules[link.product.identity] else { continue }
                    guard productModules.directlyVendsModule(root.overridenName) else { continue }
                    guard let moduleInfo = productModules.intraPackageModules[module.name]?.moduleInfo else { continue }

                    propose(
                        terminal,
                        overridenName: root.overridenName,
                        for: moduleInfo,
                        vendingProducts: moduleAlias.vendingProducts,
                        originatingPackage: moduleAlias.package,
                        isRootDeclaration: isRootDeclaration
                    )
                }

                let affectedProducts = moduleAlias.vendingProducts.compactMap({ self.productModules[$0]?.crossPackageDependentProducts }).flatMap({$0})

                for affectedProduct in affectedProducts {
                    guard let product = self.productModules[affectedProduct] else { continue }
                    for reachable in product.intraPackageModules where product.directlyVendsModule(reachable.moduleInfo) {
                        propose(
                            terminal,
                            overridenName: root.overridenName,
                            for: reachable.moduleInfo,
                            vendingProducts: moduleAlias.vendingProducts,
                            originatingPackage: moduleAlias.package,
                            isRootDeclaration: isRootDeclaration
                        )
                    }
                }
            }
        }

        func hasSurvivor(_ proposedAlias: ProposedAlias, for module: ModuleInfo) -> Bool {
            let products = self.vendingProducts(for: module).compactMap { self.productModules[$0] }
            for product in products {
                for other in product.reachableModules(named: proposedAlias.canonicalModuleName) {
                    let id = ModuleAlias.ModuleAliasID(moduleName: proposedAlias.canonicalModuleName, packageIdentity: other.packageId)
                    if self.moduleAliases[id] == nil {
                        return true
                    }
                }
            }
            return false
        }

        func closestCandidate(_ proposedAlias: ProposedAlias, for moduleInfo: ModuleInfo) -> ProposedAlias.Candidate? {
            let vendingProducts = self.vendingProducts(for: moduleInfo)
            let candidatePackages = Set(proposedAlias.candidates.map(\.originatingPackage))

            // Distance is already precomputed by computeAllReachableModules(), and grouped by
            // literal name in reachableModulesByName — a direct lookup covers both the
            // same-package and cross-package cases, no BFS or full-set scan needed.
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

            // A genuine tie (multiple candidates equally close) has no real winner — return
            // nil rather than picking one arbitrarily.
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

        for (moduleInfo, proposals) in proposedAliases {
            for rawProposedAlias in proposals {
                var proposedAlias = rawProposedAlias
                proposedAlias.candidates = preferContinuedOverRoot(proposedAlias.candidates)
                let winner: String?

                // A module renaming itself always wins outright — its own identity change isn't
                // gated on unrelated same-named modules also being reachable through it.
                if let selfRename = proposedAlias.candidates.first(where: { $0.isSelfRename }) {
                    winner = selfRename.terminalAlias
                } else if hasSurvivor(proposedAlias, for: moduleInfo) {
                    winner = nil
                } else if proposedAlias.candidates.count == 1, let alias = proposedAlias.candidates.first {
                    winner = alias.terminalAlias
                } else if let samePackage = proposedAlias.candidates.first(where: { $0.originatingPackage == moduleInfo.packageId }) {
                    winner = samePackage.terminalAlias
                } else {
                    let allSelfDeclared = proposedAlias.candidates.filter { $0.declaringModule == moduleInfo.module }
                    if allSelfDeclared.count > 1 {
                        // Self-authored ambiguity: this module declared multiple conflicting
                        // renames for the same literal name — it can't tell which one it meant either.
                        winner = nil
                    } else if let onlySelfDeclared = allSelfDeclared.first {
                        // Exactly one self-declaration. If it's a root declaration, this module
                        // already resolved its own literal name unambiguously by writing the
                        // alias — it isn't a genuine consumer of the broadcast, so fall through
                        // to distance instead of trusting it directly.
                        winner = onlySelfDeclared.isRootDeclaration
                            ? closestCandidate(proposedAlias, for: moduleInfo)?.terminalAlias
                            : onlySelfDeclared.terminalAlias
                    } else {
                        winner = closestCandidate(proposedAlias, for: moduleInfo)?.terminalAlias
                    }
                }
                if let winner {
                    let module = moduleInfo.module
                    module.addModuleAlias(for: proposedAlias.canonicalModuleName, as: winner)
                    // Check against non swift files in the module's sources and warn accordingly.
                    if module.sources.containsNonSwiftFiles, let aliases = module.moduleAliases {
                        let aliasesMsg = aliases.map({ "'\($0.key)' as '\($0.value)'" }).joined(separator: ", ")

                        for product in proposedAlias.vendingProducts {
                            guard let product = self.productModules[product] else { continue }
                            observabilityScope.emit(warning: "target '\(module.name)' for product '\(product.productName)' from package '\(moduleInfo.packageId)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols")
                        }
                    }
                }
            }
        }

        // Apply all aliases
        for moduleAlias in self.moduleAliases {
            moduleAlias.applyAlias()
        }

        // Diagnose unapplied aliases.
        for moduleAlias in self.moduleAliases where moduleAlias.terminalAliases.isEmpty {
            if let diagnosedAlias = moduleAlias.aliases.first(where: { $0.overridenName == moduleAlias.module.name }) {
                observabilityScope.emit(warning: "module alias for target '\(moduleAlias.module.name)', declared in package '\(diagnosedAlias.declaringPackage)', does not match any recursive target dependency of product '\(diagnosedAlias.product.name)' from package '\(moduleAlias.package.description)'")
            }
        }
    }
}

public class ModuleAlias: Identifiable {
    public typealias ID = ModuleAliasID
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

        // Does the alias conflict with another existing alias?
        // (IdentifiableSet dedupes by Alias.id = (name, declaringPackage); a re-insertion of an
        // alias with an id that's already present is always identical in every other field too,
        // since name is part of the id — so a duplicate insert is always a harmless no-op.)
        guard self.aliases.insert(alias).inserted else { return }
        // Also insert in reverse-lookup
        self.reverseLookupAliases[alias.reverseId, default: []].append(alias.id)
        // Multiple different names for the same overridden name/originating package is only
        // a genuine conflict when the SAME declaring package is responsible for more than one
        // of them — that's a single entity being self-contradictory. When the conflicting names
        // come from different, unrelated declaring packages (e.g. two independent paths through
        // the graph that each alias the same canonical module differently), it's a legitimate
        // diverged chain, resolved later by propose()'s tie-breaking — not an error here.
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
