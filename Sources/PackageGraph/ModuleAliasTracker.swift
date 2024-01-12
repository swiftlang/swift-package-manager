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
    var idToProductToAllTargets = [PackageIdentity: [String: [Target]]]()
    var productToDirectTargets = [String: [Target]]()
    var productToAllTargets = [String: [Target]]()
    var parentToChildProducts = [String: [String]]()
    var parentToChildIDs = [PackageIdentity: [PackageIdentity]]()
    var childToParentID = [PackageIdentity: PackageIdentity]()
    var appliedAliases = Set<String>()

    init() {}
    mutating func addTargetAliases(targets: [Target], package: PackageIdentity) throws {
        let targetDependencies = targets.map{$0.dependencies}.flatMap{$0}
        for dep in targetDependencies {
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
            let existingAliases = aliasDict.values.flatMap{$0}.filter {  aliases.keys.contains($0.name) }
            for existingAlias in existingAliases {
                if let newAlias = aliases[existingAlias.name], newAlias != existingAlias.alias {
                    // Error if there are multiple different aliases specified for
                    // targets in this product
                    throw PackageGraphError.multipleModuleAliases(target: existingAlias.name, product: productName, package: originPackage.description, aliases: existingAliases.map{$0.alias} + [newAlias])
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
    mutating func trackTargetsPerProduct(product: Product, package: PackageIdentity) {
        let targetDeps = product.targets.map{$0.dependencies}.flatMap{$0}
        var allTargetDeps = product.targets.map{$0.recursiveDependentTargets.map{$0.dependencies}}.flatMap{$0}.flatMap{$0}
        allTargetDeps.append(contentsOf: targetDeps)
        for dep in allTargetDeps {
            if case let .product(depRef, _) = dep {
                parentToChildProducts[product.identity, default: []].append(depRef.identity)
            }
        }

        var allTargetsInProduct = targetDeps.compactMap{$0.target}
        allTargetsInProduct.append(contentsOf: product.targets)
        idToProductToAllTargets[package, default: [:]][product.identity] = allTargetsInProduct
        productToDirectTargets[product.identity] = product.targets
        productToAllTargets[product.identity] = allTargetsInProduct
    }

    func validateAndApplyAliases(product: Product,
                                 package: PackageIdentity,
                                 observabilityScope: ObservabilityScope) throws {
        guard let targets = idToProductToAllTargets[package]?[product.identity] else { return }
        let targetsWithAliases = targets.filter{ $0.moduleAliases != nil }
        for targetWithAlias in targetsWithAliases {
            if targetWithAlias.sources.containsNonSwiftFiles {
                let aliasesMsg = targetWithAlias.moduleAliases?.map{"'\($0.key)' as '\($0.value)'"}.joined(separator: ", ") ?? ""
                observabilityScope.emit(warning: "target '\(targetWithAlias.name)' for product '\(product.name)' from package '\(package.description)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols")
            }
            targetWithAlias.applyAlias()
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

        if let productToAllTargets = idToProductToAllTargets[rootPkg] {
            // First, propagate aliases upstream
            for productID in productToAllTargets.keys {
                var aliasBuffer = [String: ModuleAliasModel]()
                propagate(productID: productID, observabilityScope: observabilityScope, aliasBuffer: &aliasBuffer)
            }

            // Then, merge or override upstream aliases downwards
            for productID in productToAllTargets.keys {
                merge(productID: productID, observabilityScope: observabilityScope)
            }
        }
        // Finally, fill in aliases for targets in products that are in the
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

        if let curDirectTargets = productToDirectTargets[productID] {
            var relevantTargets = curDirectTargets.map{$0.recursiveDependentTargets}.flatMap{$0}
            relevantTargets.append(contentsOf: curDirectTargets)

            for relTarget in relevantTargets {
                if let val = lookupAlias(key: relTarget.name, in: aliasBuffer) {
                    appliedAliases.insert(relTarget.name)
                    relTarget.addModuleAlias(for: relTarget.name, as: val)
                    if let prechainVal = aliasBuffer[relTarget.name],
                       prechainVal.alias != val {
                        relTarget.addPrechainModuleAlias(for: relTarget.name, as: prechainVal.alias)
                        appliedAliases.insert(prechainVal.alias)
                        relTarget.addPrechainModuleAlias(for: prechainVal.alias, as: val)
                        observabilityScope.emit(info: "Module alias '\(prechainVal.alias)' defined in package '\(prechainVal.consumingPackage)' for target '\(relTarget.name)' in package/product '\(productID)' is overridden by alias '\(val)'; if this override is not intended, remove '\(val)' from 'moduleAliases' in its manifest")
                        aliasBuffer.removeValue(forKey: prechainVal.alias)

                        // Since we're overriding an alias here, we have to pretend it was applied to avoid follow-on warnings.
                        var currentAlias: String? = val
                        while let _currentAlias = currentAlias, !appliedAliases.contains(_currentAlias) {
                            appliedAliases.insert(_currentAlias)
                            currentAlias = aliasBuffer.values.first { $0.alias == _currentAlias }?.name
                        }
                    }
                    aliasBuffer.removeValue(forKey: relTarget.name)
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

        if let curDirectTargets = productToDirectTargets[productID] {
            let depTargets = curDirectTargets.map{$0.recursiveDependentTargets}.flatMap{$0}
            let depTargetAliases = toDictionary(depTargets.compactMap{$0.moduleAliases})
            let depChildTargets = dependencyProductTargets(of: depTargets)
            let depChildAliases = toDictionary(depChildTargets.compactMap{$0.moduleAliases})
            let depChildPrechainAliases = toDictionary(depChildTargets.compactMap{$0.prechainModuleAliases})
            chainModuleAliases(targets: depTargets,
                               checkedTargets: depTargets,
                               targetAliases: depTargetAliases,
                               childTargets: depChildTargets,
                               childAliases: depChildAliases,
                               childPrechainAliases: depChildPrechainAliases,
                               observabilityScope: observabilityScope)

            let relevantTargets = depTargets + curDirectTargets
            let targetAliases = toDictionary(relevantTargets.compactMap{$0.moduleAliases})
            let depProductTargets = dependencyProductTargets(of: relevantTargets)
            var depProductAliases = [String: [String]]()
            let depProductPrechainAliases = toDictionary(depProductTargets.compactMap{$0.prechainModuleAliases})

            for depProdTarget in depProductTargets {
                let depProdTargetAliases = depProdTarget.moduleAliases ?? [:]
                for (key, val) in depProdTargetAliases {
                    var shouldAddAliases = false
                    if depProdTarget.name == key {
                        shouldAddAliases = true
                    } else if !depProductTargets.map({$0.name}).contains(key) {
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
            chainModuleAliases(targets: curDirectTargets,
                               checkedTargets: relevantTargets,
                               targetAliases: targetAliases,
                               childTargets: depProductTargets,
                               childAliases: depProductAliases,
                               childPrechainAliases: depProductPrechainAliases,
                               observabilityScope: observabilityScope)
        }
    }

    // This fills in aliases for targets in products that are in the dependency
    // chain but not in a product consumed by other packages. Such targets still
    // need to have aliases applied to them so they can be built with correct
    // dependent binary names
    mutating func fillInRest(package: PackageIdentity) {
        if let productToTargets = idToProductToAllTargets[package] {
            for (_, productTargets) in productToTargets {
                let unAliased = productTargets.contains{$0.moduleAliases == nil}
                if unAliased {
                    for target in productTargets {
                        let depAliases = target.recursiveDependentTargets.compactMap{$0.moduleAliases}.flatMap{$0}
                        for (key, alias) in depAliases {
                            appliedAliases.insert(key)
                            target.addModuleAlias(for: key, as: alias)
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
        targets: [Target],
        checkedTargets: [Target],
        targetAliases: [String: [String]],
        childTargets: [Target],
        childAliases: [String: [String]],
        childPrechainAliases: [String: [String]],
        observabilityScope: ObservabilityScope
    ) {
        guard !targets.isEmpty else { return }
        var aliasDict = [String: String]()
        var prechainAliasDict = [String: [String]]()
        var directRefAliasDict = [String: [String]]()
        let childDirectRefAliases = toDictionary(childTargets.compactMap{$0.directRefAliases})
        for (childTargetName, childTargetAliases) in childAliases {
            // Tracks whether to add prechain aliases to targets
            var addPrechainAliases = false
            // Current targets and their dependents contain this child product
            // target name
            if checkedTargets.map({$0.name}).contains(childTargetName) {
                addPrechainAliases = true
            }
            if let overlappingTargetAliases = targetAliases[childTargetName], !overlappingTargetAliases.isEmpty {
                // Current target aliases have the same key as this child
                // target name, so the child target alias should not be applied
                addPrechainAliases = true
                aliasDict[childTargetName] = overlappingTargetAliases.first
            } else if childTargetAliases.count > 1 {
                // Multiple aliases from different products for this child target
                // name exist so they should not be applied; their aliases / new
                // names should be used directly
                addPrechainAliases = true
            } else if childTargets.filter({$0.name == childTargetName}).count > 1 {
                // Targets from different products have the same name as this child
                // target name, so their aliases should not be applied
                addPrechainAliases = true
            }

            if addPrechainAliases {
                if let prechainAliases = childPrechainAliases[childTargetName] {
                   for prechainAliasKey in prechainAliases {
                       if let prechainAliasVals = childPrechainAliases[prechainAliasKey] {
                           // If aliases are chained, keep track of prechain
                           // aliases
                           prechainAliasDict[prechainAliasKey, default: []].append(contentsOf: prechainAliasVals)
                           // Add prechained aliases to the list of aliases
                           // that should be directly referenced in source code
                           directRefAliasDict[childTargetName, default: []].append(prechainAliasKey)
                           directRefAliasDict[prechainAliasKey, default: []].append(contentsOf: prechainAliasVals)
                       }
                    }
                } else if aliasDict[childTargetName] == nil {
                    // If not added to aliasDict, use the renamed module directly
                    directRefAliasDict[childTargetName, default: []].append(contentsOf: childTargetAliases)
                }
            } else if let productTargetAlias = childTargetAliases.first {
                if childTargetAliases.count > 1 {
                    observabilityScope.emit(warning: "There should be one alias for target '\(childTargetName)' but there are [\(childTargetAliases.map{"'\($0)'"}.joined(separator: ", "))]")
                }
                // Check if not in child targets' direct ref aliases list, then add
                if lookupAlias(value: childTargetName, in: childDirectRefAliases).isEmpty,
                   childDirectRefAliases[childTargetName] == nil {
                    aliasDict[childTargetName] = productTargetAlias
                }
            }
        }

        for target in targets {
            for (key, val) in aliasDict {
                appliedAliases.insert(key)
                target.addModuleAlias(for: key, as: val)
            }
            for (key, valList) in prechainAliasDict {
                if let val = valList.first,
                    valList.count <= 1 {
                    appliedAliases.insert(key)
                    target.addModuleAlias(for: key, as: val)
                    target.addPrechainModuleAlias(for: key, as: val)
                }
            }
            for (key, list) in directRefAliasDict {
                target.addDirectRefAliases(for: key, as: list)
                observabilityScope.emit(info: "Target '\(target.name)' has a dependency on multiple targets named '\(key)'; the aliased names are [\(list.map{"'\($0)'"}.joined(separator: ", "))] and should be used directly in source code if referenced from '\(target.name)'")
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

    private func dependencyProductTargets(of targets: [Target]) -> [Target] {
        let result = targets.map{$0.dependencies.compactMap{$0.product?.identity}}.flatMap{$0}.compactMap{productToAllTargets[$0]}.flatMap{$0}
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

extension Target {
    func dependsOn(productID: String) -> Bool {
        return self.dependencies.contains { dep in
            if case let .product(prodRef, _) = dep {
                return prodRef.identity == productID
            }
            return false
        }
    }

    var recursiveDependentTargets: [Target] {
        var list = [Target]()
        var nextDeps = self.dependencies
        while !nextDeps.isEmpty {
            let nextTargets = nextDeps.compactMap{$0.target}
            list.append(contentsOf: nextTargets)
            nextDeps = nextTargets.map{$0.dependencies}.flatMap{$0}
        }
        return list
    }
}
