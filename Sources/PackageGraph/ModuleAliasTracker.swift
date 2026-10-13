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
import Foundation



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

    // Multiple majors supplementary maps
    private let manifestsByPackage: [PackageIdentity: Manifest]
    private let bucketsByBase: [PackageIdentity: [Int: PackageIdentity]]
    private var productToPackage: [String: PackageIdentity] = [:]

    init(packages: [PackageIdentity: Package]) {
        self.manifestsByPackage = packages.mapValues(\.manifest)
        var buckets = [PackageIdentity: [Int: PackageIdentity]]()
        for id in packages.keys {
            if let major = Int(id.getMajor()) {
                buckets[id.withoutMajor(), default: [:]][major] = id
            }
        }
        self.bucketsByBase = buckets
    }

    /// The package a consumer's product reference actually links to.
    private func resolvedPackage(for ref: Module.ProductReference, consumer: PackageIdentity) -> PackageIdentity? {
        // Same rule the linker's productDependencyMap uses: match on the consumer's declared name.
        let name = (ref.package ?? ref.name).lowercased()
        guard let dependency = manifestsByPackage[consumer]?.dependencies.first(where: {
            $0.nameForModuleDependencyResolutionOnly.lowercased() == name
        }) else { return nil }

        // Not multi-major: the dependency resolves to its ordinary identity.
        guard let buckets = bucketsByBase[dependency.identity] else { return dependency.identity }

        // Multi-major: highest major that BOTH the declaration allows and actually resolved.
        let declared = Set(dependency.supportedMajorVersions)
        return buckets.filter { declared.contains($0.key) }.max(by: { $0.key < $1.key })?.value
    }

    func productID(for ref: Module.ProductReference, consumer: PackageIdentity) -> String {
        guard let package = resolvedPackage(for: ref, consumer: consumer),
              package != package.withoutMajor()          // only rewrite scoped buckets
        else { return ref.identity }                      // otherwise behave exactly as today
        return package.description.lowercased() + "_" + ref.name   // matches Product.identity
    }

    private func scopedPackage(for ref: Module.ProductReference, consumer: PackageIdentity) -> PackageIdentity? {
        guard let p = resolvedPackage(for: ref, consumer: consumer), p != p.withoutMajor() else { return nil }
        return p
    }

    mutating func addModuleAliases(modules: [Module], package: PackageIdentity) throws {
        let moduleDependencies = modules.flatMap(\.dependencies)
        for dep in moduleDependencies {
            if case let .product(productRef, _) = dep,
               let productPkg = productRef.package {
                let productPkgID = scopedPackage(for: productRef, consumer: package) ?? PackageIdentity.plain(productPkg)
                // Track dependency package ID chain
                addPackageIDChain(parent: package, child: productPkgID)
                if let aliasList = productRef.moduleAliases {
                    // Track aliases for this product
                    try addAliases(aliasList,
//                                   productID: productRef.identity,
                                   productID: productID(for: productRef, consumer: package),
                                   productName: productRef.name,
                                   originPackage: productPkgID,
                                   consumingPackage: package)
                }
            }
        }
    }

    mutating func addMultiMajorAliases(modules: [Module], products: [Product], package: PackageIdentity) throws {
        let major = package.getMajor()

        for product in products {
            // rename modules
            let productModules = product.modules + product.modules.flatMap(\.recursiveDependentModules)
            var aliases: [String: String] = [:]
            for module in productModules {
                aliases[module.name] = "\(module.name)_v\(major)"
            }
            print("Adding multi major aliases: ")
            print("\(aliases)")
            try addAliases(
                aliases,
                productID: product.identity,
                productName: product.name,
                originPackage: package,
                consumingPackage: package
            )
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
            let existingAliases = aliasDict.values.flatMap{$0}.filter {  aliases.keys.contains($0.name) }
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
                let resolvedDepRef = productID(for: depRef, consumer: package)
                print("adding parent to child product: \(depRef.identity)")
                print("the resolved dependency ref identity: \(resolvedDepRef)")
                print("dependency with appropriate version id: \(dep)")
                parentToChildProducts[product.identity, default: []].append(resolvedDepRef)
            }
        }

        var allModulesInProduct = moduleDeps.compactMap(\.module)
        allModulesInProduct.append(contentsOf: product.modules)
        idToProductToAllModules[package, default: [:]][product.identity] = allModulesInProduct
        productToDirectModules[product.identity] = product.modules
        productToAllModules[product.identity] = allModulesInProduct
        productToPackage[product.identity] = package
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
        print("propagating for \(productID)")
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
                } else {
                    print("****Unable to find alias for: \(relevantModule.name)")
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
            guard let consumer = productToPackage[productID] else { return }
            let depChildModules = dependencyProductModules(of: depModules, consumer: consumer)
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
            let depProductModules = dependencyProductModules(of: relevantModules, consumer: consumer)
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

    private func dependencyProductModules(of modules: [Module], consumer: PackageIdentity) -> [Module] {
        var result: [Module] = []
        for module in modules {
            let current = module.dependencies.compactMap({
                if let product = $0.product {
                    return productID(for: product, consumer: consumer)
                }
                return nil
            }).compactMap({ productToAllModules[$0]})
                .flatMap({ $0 })
            result.append(contentsOf: current)
        }
//        let result = modules.map{$0.dependencies.compactMap{$0.product?.identity}}.flatMap{$0}.compactMap{productToAllModules[$0]}.flatMap{$0}
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
        var list = [Module]()
        var nextDeps = self.dependencies
        while !nextDeps.isEmpty {
            let nextModules = nextDeps.compactMap{$0.module}
            list.append(contentsOf: nextModules)
            nextDeps = nextModules.map{$0.dependencies}.flatMap{$0}
        }
        return list
    }
}
