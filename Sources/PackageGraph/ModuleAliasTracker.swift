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

struct ModuleAliasTracker2 {
    /// Tracks all the module aliases
    public private(set) var moduleAliases: IdentifiableSet<ModuleAlias> = []
    fileprivate var consumingPackageAliases: [PackageIdentity: Set<ModuleAlias.ModuleAliasID>] = [:]

    /// Key: fully qualified name of a product (package id + product name)
    /// Value: list of modules that the product depends on
    fileprivate var productModules: IdentifiableSet<ProductModules> = []
    fileprivate var packageModules: [PackageIdentity: IdentifiableSet<ModuleInfo>] = [:]

    /// Flag that tracks whether module aliasing is being used in the current package graph.
    public var moduleAliasingUsed: Bool = false

    /// A model that stores direct module dependencies and the associated product, if any.
    public struct ModuleInfo: Identifiable, Hashable {
        /// The represented module.
        let module: Module
        /// A module's .module-type dependencies, defined within the same package.
        let directModuleDependencies: Set<String>
        /// The product that declared this module as a dependency.
        let productId: String?

        public var id: String {
            return module.name
        }

        public init(module: Module, productId: String? = nil) {
            self.module = module
            self.directModuleDependencies = Set(module.dependencies.compactMap(\.module).map(\.name))
            self.productId = productId
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
        let intraPackageModules: IdentifiableSet<ModuleInfo>
        /// All transitively dependent cross-package products.
        var crossPackageChildProducts: Set<String> = []
        /// All modules reachable by recursively following `crossPackageChildProducts`,
        /// i.e. each child product's own `intraPackageModules` plus its own
        /// cross-package closure. Populated by `computeAllReachableModules()` once
        /// every product in the graph is known; empty until then.
        var crossPackageReachableModules: IdentifiableSet<ModuleInfo> = []

        public var id: String {
            self.productId
        }

        public init(product: Product, package: PackageIdentity, _ modules: [Module]) {
            self.productId = product.identity
            self.productName = product.name
            self.package = package
            self.directModules = Set(modules.map(\.name))

            var queue = modules
            var visited: Set<String> = []
            var allModules: IdentifiableSet<ModuleInfo> = []
            var childProducts: Set<String> = []

            // Continue to transitively populate modules
            while !queue.isEmpty {
                let currentModule = queue.removeFirst()
                guard visited.insert(currentModule.name).inserted else { continue }
                let currentModuleInfo = ModuleInfo(module: currentModule, productId: product.identity)
                allModules.insert(currentModuleInfo)

                // Follow chain of intra-dependent modules.
                queue.append(contentsOf: currentModule.dependencies.compactMap(\.module))

                // Collect cross-package product dependencies.
                for dep in currentModule.dependencies {
                    if case let .product(productRef, _) = dep {
                        childProducts.insert(productRef.identity)
                    }
                }
            }

            self.crossPackageChildProducts = childProducts
            self.intraPackageModules = allModules
        }
    }

    public init(packages: [Package], _ observabilityScope: ObservabilityScope) throws {
        // Begin by building the a product -> module map.
        packages.forEach({ package in
            // Begin by pre-populating the product -> module map.
            // Also store the intra-package modules.
            self.addProductAndPackageModules(package)
        })

        // Second pass to fully resolve all reachable modules per product.
        self.computeAllReachableModules()

        // Second pass to register all alias declarations.
        try self.addAliases(packages)


        // Propagate aliases across the package graph, applying terminal aliases
        self.applyAliases(observabilityScope)
    }

    /// Second pass on all reachable modules for a given product in the package graph.
    private mutating func computeAllReachableModules() {
        var resolved: Set<String> = []
        var inProgress: Set<String> = []

        func resolve(for productId: String) -> IdentifiableSet<ModuleInfo> {
            guard let product = self.productModules[productId] else { return [] }
            if resolved.contains(product.productId) {
                return product.crossPackageReachableModules.union(product.intraPackageModules.values)
            }
            guard inProgress.insert(productId).inserted else {
                // Cycle guard; contribute nothing further along this path.
                return product.intraPackageModules
            }
            defer { inProgress.remove(productId) }
            var reachable = product.intraPackageModules
            for childId in product.crossPackageChildProducts {
                reachable.formUnion(resolve(for: childId).values)
            }

            self.productModules[productId]?.crossPackageReachableModules = reachable
            resolved.insert(productId)
            return reachable
        }

        for product in self.productModules.values {
            _ = resolve(for: product.productId)
//            self.productModules[product.productId]?.crossPackageReachableModules = reachableModules
        }
    }

    // First pass; add all the modules that make up each product.
    public mutating func addProductAndPackageModules(_ package: Package) {
        for product in package.products {
            // Don't redundantly populate the modules map
            // todo; if we hit this, maybe bug?
            guard productModules[product.identity] == nil else { continue }
            let modules = product.modules
            self.productModules[product.identity] = .init(product: product, package: package.identity, modules)
//            self.packageProducts[package.identity, default: []].insert(product.identity)
        }
        self.packageModules[package.identity] = IdentifiableSet(package.modules.map({ ModuleInfo(module: $0)} ))
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
                    if case let .product(productRef, _) = dep,
                       let productPkg = productRef.package,
                       let aliases = productRef.moduleAliases,
                       let modulesForProduct = self.productModules[productRef.identity]
                        {
                        if !aliases.isEmpty { self.moduleAliasingUsed = true }

                        try aliases.forEach({ alias in
                            let aliasInfo = ModuleAlias.Alias(
                                name: alias.value,
                                overridenName: alias.key,
                                product: productRef,
                                declaringPackage: consumingPackage,
                                declaringModule: module,
                                originatingPackage: .plain(productPkg)
                            )

                            // For aliases that are direct i.e. override the canonical name of a module
                            if let moduleInfo = modulesForProduct.crossPackageReachableModules[alias.key],
                               let productId = moduleInfo.productId,
                               let product = self.productModules[productId] {
                                let moduleAliasId = ModuleAlias.ModuleAliasID(
                                    moduleName: moduleInfo.module.name,
                                    packageIdentity: product.package
                                )
                                // Existing alias; add to alias chain.
                                if let existingAlias = self.moduleAliases[moduleAliasId] {
                                    try existingAlias.addAlias(
                                        aliasInfo.name,
                                        oldName: aliasInfo.overridenName,
                                        consumingPackage,
                                        module,
                                        productRef,
                                        product.package
                                    )
                                    self.consumingPackageAliases[consumingPackage, default: []].insert(existingAlias.id)
                                } else {
                                    // New alias; add to the dict.
                                    let newAlias = ModuleAlias(
                                        module: moduleInfo.module,
                                        product: product.productName,
                                        package: moduleAliasId.packageIdentity,
                                    )
                                    try newAlias.addAlias(
                                        aliasInfo.name,
                                        oldName: aliasInfo.overridenName,
                                        aliasInfo.declaringPackage,
                                        module,
                                        productRef,
                                        newAlias.package
                                    )
                                    // Update consuming package map + moduleAliases
                                    self.consumingPackageAliases[consumingPackage, default: []].insert(newAlias.id)
                                    self.moduleAliases.insert(newAlias)
                                }
                            } else if let matchingAliasId = self.consumingPackageAliases[consumingPackage]?.first(where: {
                                guard let matchingAlias = self.moduleAliases[$0] else {
                                    return false
                                }
                                return matchingAlias.canChainAlias(alias: aliasInfo)
                            }) {
                                // todo bp cleanup above
                                try self.moduleAliases[matchingAliasId]?.addAlias(
                                    aliasInfo.name,
                                    oldName: aliasInfo.overridenName,
                                    consumingPackage,
                                    module,
                                    productRef,
                                    .plain(productPkg)
                                )
                            } else {
                                // For aliases that are possibly chained; add to unresolved.
                                // We will resolve these on a second pass.

                                // There could be intra-package aliases/chains here. TODO
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
            // wrt the alias chain (if any). Take the root and check against any existing module aliases
            // that we can chain this to.
            guard let root = chain.last else { continue }
            // Check whether we can identify an existing module alias for the given package.
            let originatingPackage = root.originatingPackage

            var resolved = false
            if let moduleAliasIds = self.consumingPackageAliases[originatingPackage] {
                for id in moduleAliasIds {
                    guard let moduleAlias = self.moduleAliases[id] else { continue }
                    if moduleAlias.canChainAlias(alias: root) {
                        for alias in chain.reversed() {
                            try moduleAlias.addAlias(alias)
                            self.consumingPackageAliases[alias.declaringPackage, default: []].insert(moduleAlias.id)
                        }
                        resolved = true
                        break
                    }
                }
            }

            if !resolved {
                // Emit diagnostics for each alias in this chain
                // todo
                for alias in chain {
//                    observabilityScope.emit(warning: "module alias '\(alias.overridenName)' -> '\(alias.name)' declared in package '\(alias.consumingPackage)' could not be resolved")
                }
            }
        }

        // Assure no single package has declared more than one module alias that results in the same name
//        for package in packages {
//            let ids = self.consumingPackageAliases[package.identity] ?? []
//            let moduleAliases = ids.compactMap { self.moduleAliases[$0] }
//            let aliasNames = moduleAliases.compactMap { $0.declaredAliasForPackage(package.identity) }
//            let duplicates = Set(aliasNames).count != aliasNames.count
//            guard !duplicates else {
//                throw PackageGraphError.multipleModuleAliases(
//                    module: alias.overridenName,
//                    product: productRef.name,
//                    package: self.package.description,
//                    aliases: self.aliases.map{$0.name} + [alias.name]
//                )
//            }
//        }
    }

    // Third pass; propagate aliases
    private mutating func applyAliases(_ observabilityScope: ObservabilityScope) {
        // Validate module aliases that still need to be addressed as direct ref.
        let moduleNameToAlias = Dictionary(grouping: moduleAliases, by: { $0.module.name })

        var proposedAliases: [Module: IdentifiableSet<ProposedAlias>] = [:]

        struct ProposedAlias: Identifiable, Hashable {
            let canonicalModuleName: String
            var proposedAliases: Set<String>
            let originatingProduct: String
            let originatingPackage: PackageIdentity

            var id: String {
                canonicalModuleName
            }

            static func == (lhs: ProposedAlias, rhs: ProposedAlias) -> Bool {
                lhs.canonicalModuleName == rhs.canonicalModuleName && lhs.proposedAliases == rhs.proposedAliases
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(canonicalModuleName)
                hasher.combine(proposedAliases)
            }
        }

        for moduleAlias in self.moduleAliases {
            // Dependency cycle detection
            var visitedProducts: Set<String> = []

            func applyToProduct(_ product: String, canonicalName: String, terminalName: String) {
                guard visitedProducts.insert(product).inserted else { return }
                guard let product = self.productModules[product] else { return }
                guard product.crossPackageReachableModules[moduleAlias.module.name] != nil else { return }

                for moduleInfo in product.intraPackageModules {
                    guard moduleInfo.module.name == moduleAlias.module.name
                                  || product.directModules.contains(moduleInfo.module.name) else { continue }
                    if proposedAliases[moduleInfo.module, default: []][canonicalName] != nil {
                        proposedAliases[moduleInfo.module, default: []][canonicalName]?.proposedAliases.insert(terminalName)
                    } else {
                        proposedAliases[moduleInfo.module, default: []][canonicalName] = ProposedAlias(
                            canonicalModuleName: canonicalName,
                            proposedAliases: [terminalName],
                            originatingProduct: moduleAlias.originatingProduct,
                            originatingPackage: moduleAlias.package
                        )
                    }
                }
                for childProduct in product.crossPackageChildProducts {
                    applyToProduct(childProduct, canonicalName: canonicalName, terminalName: terminalName)
                }
            }

            // `applyToProduct` only walks *downward* through the product graph starting
            // from the product where the alias was declared. It can't reach a module that
            // lives in the aliased module's own package but is vended by a sibling
            // product with no product-graph relationship to that starting point (e.g. one
            // product vends `Utils`, an unrelated sibling product vends `Game`, and `Game`
            // has a plain intra-package dependency on `Utils`). Directly sweep every
            // module in that package instead: anything that either *is* the renamed
            // module or directly depends on it intra-package needs the alias too,
            // regardless of which product exposes it.
//            func applyToPackageSiblings(canonicalName: String, terminalName: String) {
//                for product in self.productModules.values where product.package == moduleAlias.package {
//                    for moduleInfo in product.intraPackageModules {
//                        guard moduleInfo.module.name == moduleAlias.module.name
//                            || moduleInfo.directModuleDependencies.contains(moduleAlias.module.name) else { continue }
//                        if proposedAliases[moduleInfo.module, default: []][canonicalName] != nil {
//                            proposedAliases[moduleInfo.module, default: []][canonicalName]?.proposedAliases.insert(terminalName)
//                        } else {
//                            proposedAliases[moduleInfo.module, default: []][canonicalName] = ProposedAlias(
//                                canonicalModuleName: canonicalName,
//                                proposedAliases: [terminalName],
//                                originatingProduct: moduleAlias.originatingProduct,
//                                originatingPackage: moduleAlias.package
//                            )
//                        }
//                    }
//                }
//            }

            let chains = moduleAlias.applyChainedAliases(observabilityScope)
            let hasDivergingAliasChains = moduleAlias.terminalAliases.count > 1

            for chain in chains {
                guard let root = chain.chain.first else { continue }
                let terminal = chain.terminalAlias
//                let product = root.declaringPackage

                // Every link's declaring module is a write candidate. The collision
                // check in the final apply loop (count > 1 -> drop) is what resolves
                // genuine ambiguity between two unrelated real modules sharing a bare
                // name (e.g. two different chains both terminating at the same module),
                // so chain length alone must not gate this — suppressing a single-hop
                // chain's write here would silently remove one side of that collision
                // and let the other "win" instead of being dropped.
                for link in chain.chain {
                    let module = link.declaringModule
                    let package = link.declaringPackage
                    let productName = link.product.name // todo bp is correct for error msg?

                    // This link's declaringModule only has a genuine need for this
                    // write if the product it declared ITS OWN alias on directly
                    // vends a target literally named `link.overridenName`. If that
                    // name is only reachable transitively through that product
                    // (e.g. via some other target inside it), this module never
                    // itself imports the bare name — the write belongs to whichever
                    // module actually vends or depends on it directly, reached
                    // either by a later link in this chain, `applyToProduct`, or the
                    // package-sibling sweep below.
                    guard self.productModules[link.product.identity]?.directModules.contains(link.overridenName) ?? false else { continue }

                    // If this module already has its own unrelated, unaliased direct
                    // dependency (a sibling target, or a vended target of a product it
                    // depends on) literally named `root.overridenName`, don't clobber
                    // that name's meaning by writing the alias here.
                    let hasConflictingDirectDependency = module.dependencies.contains { dep in
                        switch dep {
                        case .module(let target, _):
                            return target.name == root.overridenName
                        case .product(let ref, _):
                            guard ref.moduleAliases?[root.overridenName] == nil else { return false }
                            return self.productModules[ref.identity]?.directModules.contains(root.overridenName) ?? false
                        }
                    }
                    guard !hasConflictingDirectDependency else { continue }

                    if proposedAliases[module, default: []][root.overridenName] != nil {
                        proposedAliases[module, default: []][root.overridenName]?.proposedAliases.insert(terminal.name)
                    } else {
                        proposedAliases[module, default: []][root.overridenName] = ProposedAlias(
                            canonicalModuleName: root.overridenName,
                            proposedAliases: [terminal.name],
                            originatingProduct: moduleAlias.originatingProduct,
                            originatingPackage: moduleAlias.package
                        )
                    }
                    observabilityScope.emit(info: "Module alias '\(link.name)' defined in package '\(link.declaringPackage)' for target '\(module.name)' in package/product '\(productName)' is overridden by alias '\(terminal.name)'; if this override is not intended, remove '\(terminal.name)' from 'moduleAliases' in its manifest")
                }
                applyToProduct(root.product.identity, canonicalName: root.overridenName, terminalName: terminal.name)
//                applyToPackageSiblings(canonicalName: root.overridenName, terminalName: terminal.name)
                if let modulesInOriginatingPackage = self.packageModules[moduleAlias.package]?.map(\.module) {
                    for siblingModule in modulesInOriginatingPackage {
                        if siblingModule.dependencies.contains(where: { dep in
                            switch dep {
                            case .module(let target, _):
                                return target.name == root.overridenName
                            default:
                                return false
                            }
                        }) {
                            if proposedAliases[siblingModule, default: []][root.overridenName] != nil {
                                proposedAliases[siblingModule, default: []][root.overridenName]?.proposedAliases.insert(terminal.name)
                            } else {
                                proposedAliases[siblingModule, default: []][root.overridenName] = ProposedAlias(
                                    canonicalModuleName: root.overridenName,
                                    proposedAliases: [terminal.name],
                                    originatingProduct: moduleAlias.originatingProduct,
                                    originatingPackage: moduleAlias.package
                                )
                            }
                        }
                    }
                }
            }
        }


        for (module, proposedAliases) in proposedAliases {
            for proposedAlias in proposedAliases {
                if proposedAlias.proposedAliases.count == 1, let alias = proposedAlias.proposedAliases.first {
                    module.addModuleAlias(for: proposedAlias.canonicalModuleName, as: alias)
                    // Check against non swift files in the module's sources and warn accordingly.
                    if module.sources.containsNonSwiftFiles, let aliases = module.moduleAliases {
                        let aliasesMsg = aliases.map({ "'\($0.key)' as '\($0.value)'" }).joined(separator: ", ")
                        observabilityScope.emit(warning: "target '\(module.name)' for product '\(proposedAlias.originatingProduct)' from package '\(proposedAlias.originatingPackage)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols")
                    }
                }
            }
        }
        // Apply all aliases
        for moduleAlias in self.moduleAliases {
            // All cases addressed;
            // Apply the alias to the module.
            moduleAlias.applyAlias()
        }

        // Diagnose unapplied aliases.
        for moduleAlias in self.moduleAliases where moduleAlias.terminalAliases.isEmpty {
            if let diagnosedAlias = moduleAlias.aliases.first(where: { $0.overridenName == moduleAlias.module.name }) {
                // diagnose
                observabilityScope.emit(warning: "module alias for target '\(moduleAlias.module.name)', declared in package '\(diagnosedAlias.declaringPackage)', does not match any recursive target dependency of product '\(diagnosedAlias.product.name)' from package '\(moduleAlias.package.description)'")
            }
        }
    }
}

public class ModuleAlias: Identifiable {
    public typealias ID = ModuleAliasID
    var module: Module
    var originatingProduct: String
    var products: Set<ProductInfo> = []
    let package: PackageIdentity
    /// Flat list of all aliases (chained, etc.) for this module.
    var aliases: IdentifiableSet<Alias> = []
    var reverseLookupAliases: [Alias.AliasId: [Alias.AliasId]] = [:]
    /// A list of paths of chained aliases, if applicable. The returned Alias represents the terminal alias in the chain.
    /// It's possible that there are multiple terminal aliases for a singular module depending on whether the alias
    /// chains have diverged in the package graph.
//    var aliasChains: [PackageIdentity: [Alias]] = [:]
    /// Represents all terminal aliases (i.e. the final overridden name for a module) in the package graph.
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

    struct ProductInfo: Hashable {
        public let name: String
        public let identity: String
        public let package: String?

        public init(_ productRef: Module.ProductReference) {
            self.name = productRef.name
            self.identity = productRef.identity
            self.package = productRef.package
        }

        public init(_ name: String, _ identity: String, package: String?) {
            self.name = name
            self.identity = identity
            self.package = package
        }
    }

    init(
        module: Module,
        product: String,
        package: PackageIdentity
    ) {
        self.module = module
        self.originatingProduct = product
        self.package = package
    }

    public struct AliasChain {
        lazy var consumingPackagesToAlias: [PackageIdentity: Alias] = {
            var result: [PackageIdentity: Alias] = [:]

            for alias in chain {
                result[alias.declaringPackage] = alias
            }

            return result
        }()
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

    func canChainAlias(alias: Alias) -> Bool {
        // Check either that this alias overrides another alias OR is being overriden by an existing alias.
        return self.aliases[.init(name: alias.overridenName, declaringPackage: alias.originatingPackage)] != nil || self.aliases.contains(where: { $0.reverseId == alias.id })
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

    func addAlias(_ alias: String, oldName: String, _ consumingPackage: PackageIdentity, _ declaringModule: Module, _ productRef: Module.ProductReference, _ originatingPackage: PackageIdentity) throws {
        // Add to list of products that this module is a dependency of.
        self.products.insert(.init(productRef))

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
        let (inserted, existing) = self.aliases.insert(alias)
        if inserted {
            // Also insert in reverse-lookup
            self.reverseLookupAliases[alias.reverseId, default: []].append(alias.id)
            // Assure that the alias name does not conflict
            if let aliases = self.reverseLookupAliases[alias.reverseId], aliases.count > 1 {
                throw PackageGraphError.multipleModuleAliases(
                    module: alias.overridenName,
                    product: productRef.name,
                    package: self.package.description,
                    aliases: aliases.map{ $0.name }
                )
            }
        }
        if !inserted && existing.name != alias.name {
            // Not referring to the same
            if existing.product.package != self.package.description {
                // shouldnt ever get here, todo remove
            } else {
                throw PackageGraphError.multipleModuleAliases(
                    module: alias.overridenName,
                    product: productRef.name,
                    package: self.package.description,
                    aliases: self.aliases.map{$0.name} + [alias.name]
                )
            }
        }
    }

    func declaredAliasForPackage(_ package: PackageIdentity) -> Alias? {
        return self.aliases.first(where: { $0.declaringPackage == package })
    }
}
