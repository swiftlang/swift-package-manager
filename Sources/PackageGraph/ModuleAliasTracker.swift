import PackageModel
import Basics

// This is a helper class that tracks module aliases in a package dependency graph
// and handles overriding upstream aliases where alises themselves conflict
class ModuleAliasTracker {
    var aliasMap = [String: [ModuleAliasModel]]()
    var idToAliasMap = [PackageIdentity: [String: [ModuleAliasModel]]]()
    var idToProductToAllTargets = [PackageIdentity: [String: [Target]]]()
    var productToDirectTargets = [String: [Target]]()
    var productToAllTargets = [String: [Target]]()
    var parentToChildProducts = [String: [String]]()
    var parentToChildIDs = [PackageIdentity: [PackageIdentity]]()
    var childToParentID = [PackageIdentity: PackageIdentity]()

    init() {}
    func addTargetAliases(targets: [Target], package: PackageIdentity) throws {
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
                                   productID: productRef.ID,
                                   productName: productRef.name,
                                   originPackage: productPkgID,
                                   consumingPackage: package)
                }
            }
        }
    }

    func addAliases(_ aliases: [String: String],
                    productID: String,
                    productName: String,
                    originPackage: PackageIdentity,
                    consumingPackage: PackageIdentity) throws {
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
            let model = ModuleAliasModel(name: originalName, alias: newName, originPackage: originPackage, consumingPackage: consumingPackage)
            idToAliasMap[originPackage, default: [:]][productID, default: []].append(model)
            aliasMap[productID, default: []].append(model)
        }
    }

    func addPackageIDChain(parent: PackageIdentity,
                           child: PackageIdentity) {
        if parentToChildIDs[parent]?.contains(child) ?? false {
            // Already added
        } else {
            parentToChildIDs[parent, default: []].append(child)
            // Used to track the top-most level package
            childToParentID[child] = parent
        }
    }

    // This func should be called once per product
    func trackTargetsPerProduct(product: Product,
                                package: PackageIdentity) {
        let targetDeps = product.targets.map{$0.dependencies}.flatMap{$0}
        var allTargetDeps = product.targets.map{$0.dependentTargets().map{$0.dependencies}}.flatMap{$0}.flatMap{$0}
        allTargetDeps.append(contentsOf: targetDeps)
        for dep in allTargetDeps {
            if case let .product(depRef, _) = dep {
                parentToChildProducts[product.ID, default: []].append(depRef.ID)
            }
        }

        var allTargetsInProduct = targetDeps.compactMap{$0.target}
        allTargetsInProduct.append(contentsOf: product.targets)
        idToProductToAllTargets[package, default: [:]][product.ID] = allTargetsInProduct
        productToDirectTargets[product.ID] = product.targets
        productToAllTargets[product.ID] = allTargetsInProduct
    }

    func validateAndApplyAliases(product: Product,
                                 package: PackageIdentity) throws {
        guard let targets = idToProductToAllTargets[package]?[product.ID] else { return }
        let targetsWithAliases = targets.filter{ $0.moduleAliases != nil }
        for target in targetsWithAliases {
            if target.sources.containsNonSwiftFiles {
                throw PackageGraphError.invalidSourcesForModuleAliasing(target: target.name, product: product.name, package: package.description)
            }
            target.applyAlias()
        }
    }

    func propagateAliases(observabilityScope: ObservabilityScope) {
        // First get the root package ID
        var pkgID = childToParentID.first?.key
        var rootPkg = pkgID
        while pkgID != nil {
            rootPkg = pkgID
            // pkgID is not nil here so can be force unwrapped
            pkgID = childToParentID[pkgID!]
        }
        guard let rootPkg = rootPkg else { return }

        if let productToAllTargets = idToProductToAllTargets[rootPkg] {
            // First, propagate aliaes upstream
            for productID in productToAllTargets.keys {
                var aliasBuffer = [String: ModuleAliasModel]()
                propagate(productID: productID, aliasBuffer: &aliasBuffer)
            }
            
            // Then, merge or override upstream aliases downwards
            for productID in productToAllTargets.keys {
                var parentList = [String: ModuleAliasModel]()
                merge(productID: productID, aliasBuffer: &parentList, observabilityScope: observabilityScope)
            }
        }
        // Finally, fill in aliases for targets in products that are in the
        // dependency chain but not in a product consumed by other packages
        fillInRest(package: rootPkg)
    }

    // Propagate defined aliases upstream. If they are chained, the final
    // alias value will be applied
    func propagate(productID: String,
                   aliasBuffer: inout [String: ModuleAliasModel]) {
        let productAliases = aliasMap[productID] ?? []
        for aliasModel in productAliases {
            // Alias buffer is used to carry down aliases defined upstream
            if aliasBuffer[aliasModel.name] == nil {
                if let v = lookupAlias(key: aliasModel.alias, in: aliasBuffer),
                   v != aliasModel.alias {
                    let chainedModel = ModuleAliasModel(name: aliasModel.name, alias: v, originPackage: aliasModel.originPackage, consumingPackage: aliasModel.consumingPackage)
                    aliasBuffer[aliasModel.name] = chainedModel
                } else {
                    aliasBuffer[aliasModel.name] = aliasModel
                }
            }
        }
        var used = [String]()
        if let curAllTargets = productToAllTargets[productID] {
            // Apply aliases to targets that are renamable, i.e. eventually
            // get renamed with an alias
            let targetsToRename = curAllTargets.filter{ aliasBuffer[$0.name] != nil }
            for curTarget in targetsToRename {
                if let aliasVal = lookupAlias(key: curTarget.name, in: aliasBuffer) {
                    let prechain = lookupAlias(value: aliasVal, in: aliasBuffer).filter { $0 != curTarget.name }
                    if let prechainKey = prechain.first {
                        used.append(prechainKey)
                    }
                    curTarget.addModuleAlias(for: curTarget.name, as: aliasVal)
                    used.append(curTarget.name)
                }
            }
        }
        for usedKey in used {
            aliasBuffer.removeValue(forKey: usedKey)
        }
        guard let children = parentToChildProducts[productID] else {
            return
        }
        for childID in children {
            propagate(productID: childID, aliasBuffer: &aliasBuffer)
        }
    }

    // Merge all the upstream aliases and override them if necessary
    func merge(productID: String,
               aliasBuffer: inout [String: ModuleAliasModel],
               observabilityScope: ObservabilityScope) {
        let productAliases = aliasMap[productID] ?? []
        for aliasModel in productAliases {
            if aliasBuffer[aliasModel.name] == nil {
                aliasBuffer[aliasModel.name] = aliasModel
            }
        }

        if let curDirectTargets = productToDirectTargets[productID],
            let curAllTargets = productToAllTargets[productID] {
            var targetsToRename = [Target]()
            // Keep track of the aliases applied to renamable targets
            // and remove the used aliases from the buffer
            for curTarget in curAllTargets {
                if let aliasVal = lookupAlias(key: curTarget.name, in: aliasBuffer),
                   let appliedAlias = curTarget.moduleAliases?[curTarget.name],
                   aliasVal == appliedAlias {
                    targetsToRename.append(curTarget)
                    aliasBuffer.removeValue(forKey: curTarget.name)
                }
            }
            
            let aliasesForTargetsToRename = targetsToRename.compactMap{$0.moduleAliases}.flatMap{$0}
            let otherTargets = curDirectTargets.filter{!targetsToRename.map{$0.name}.contains($0.name)}
            // Apply the aliases of the renamable targets to their depending targets
            for otherTarget in otherTargets {
                for (entryKey, entryVal) in aliasesForTargetsToRename {
                    otherTarget.addModuleAlias(for: entryKey, as: entryVal)
                }
            }
        }
        guard let children = parentToChildProducts[productID] else {
            return
        }
        for childID in children {
            merge(productID: childID,
                  aliasBuffer: &aliasBuffer,
                  observabilityScope: observabilityScope)
        }
        
        if let curDirectTargets = productToDirectTargets[productID],
           let curAllTargets = productToAllTargets[productID] {
            // Create a per-target alias map that stores aliases of dependent
            // targets and dependent product targets
            let depTargets = curDirectTargets
                .map{$0.dependentTargets()}.flatMap{$0}
            let depProductTargets = curAllTargets
                .map{$0.dependencies.compactMap{$0.product?.ID}}.flatMap{$0}
                .compactMap{productToAllTargets[$0]}.flatMap{$0}
            let depTargetsDepProductTargets = depTargets
                .map{$0.dependencies.compactMap{$0.product?.ID}}.flatMap{$0}
                .compactMap{productToAllTargets[$0]}.flatMap{$0}
            let depTargetAliases = depTargets.compactMap{$0.moduleAliases}.flatMap{$0}
            let depProductTargetAliases = depProductTargets.compactMap{$0.moduleAliases}.flatMap{$0}
            let depTargetDepProductTargetAliases = depTargetsDepProductTargets.compactMap{$0.moduleAliases}.flatMap{$0}
            var depAliasMap = [String: [String: [String]]]()

            // Per-target alias map for the direct targets of this product
            for directTarget in curDirectTargets {
                depAliasMap[directTarget.name] = [:]
                for (key, alias) in depTargetAliases + depProductTargetAliases {
                    if depAliasMap[directTarget.name, default: [:]][key]?.contains(alias) ?? false {
                        // do not add this alias if it's already in the list
                    } else {
                        depAliasMap[directTarget.name, default: [:]][key, default: []].append(alias)
                    }
                }
            }
            // Per-target alias map for dependent targets of the product direct targets
            for depTarget in depTargets {
                depAliasMap[depTarget.name] = [:]
                for (key, alias) in depTargetAliases + depTargetDepProductTargetAliases {
                    if depAliasMap[depTarget.name, default: [:]][key]?.contains(alias) ?? false {
                        // do not add this alias if it's already in the list
                    } else {
                        depAliasMap[depTarget.name, default: [:]][key, default: []].append(alias)
                    }
                }
            }

            let targetList = curDirectTargets + depTargets
            for targetToResolve in targetList {
                guard let relevantAliasMap = depAliasMap[targetToResolve.name] else { continue }
                for (key, aliases) in relevantAliasMap {
                    // First check if there's a target named `key` in
                    // the direct or dependent targets
                    if targetList.map({$0.name}).contains(key) {
                        // Check if those targets have module aliases for this `key`
                        let existingAliases = targetList.filter{$0.name == key}.compactMap{$0.moduleAliases?[key]}
                        for existingAlias in existingAliases {
                            if let aliasVal = targetToResolve.moduleAliases?[key], aliasVal != existingAlias {
                                // This check is added just out of precaution but
                                // shoudln't be needed
                            } else {
                                targetToResolve.addModuleAlias(for: key, as: existingAlias)
                                let prechain = lookupAlias(value: existingAlias, in: aliasBuffer).filter { $0 != key }
                                if let prechainKey = prechain.first {
                                    aliasBuffer.removeValue(forKey: prechainKey)
                                }
                            }
                        }
                        // Check if pre-chain aliases need to be added
                        let unusedAliases = aliases.filter{!existingAliases.contains($0)}
                        for alias in unusedAliases {
                            let prechain = lookupAlias(value: alias, in: aliasBuffer).filter { $0 != key }
                            if let prechainKey = prechain.first {
                                observabilityScope.emit(info: "Target '\(targetToResolve.name)' already has a dependency target named '\(key)' but has a duplicate target in a dependency product; when referencing the latter in source code, use the aliased name '\(alias)' directly")
                                // Add a prechain alias from the buffer
                                targetToResolve.addModuleAlias(for: prechainKey, as: alias)
                                aliasBuffer.removeValue(forKey: prechainKey)
                            }
                        }
                    }
                    else {
                        let targetsNamedKeyInDepProduct = depProductTargets.filter{$0.name == key}
                        if aliases.count == 1, let aliasVal = aliases.first {
                            // There's only one alias to merge and targets with
                            // name `key` in dependency products all have different
                            // aliases
                            if targetsNamedKeyInDepProduct.filter({$0.moduleAliases == nil}).isEmpty {
                                let prechain = lookupAlias(value: aliasVal, in: aliasBuffer).filter { $0 != key }
                                if let prechainKey = prechain.first {
                                    aliasBuffer.removeValue(forKey: prechainKey)
                                }
                                targetToResolve.addModuleAlias(for: key, as: aliasVal)
                                aliasBuffer.removeValue(forKey: key)
                            }
                        } else {
                            if targetsNamedKeyInDepProduct.count == 1 {
                                // There are multiple aliases for the `key`
                                // and dependency products have targets named
                                // `key`
                                let aliasesInDepProductForKeyNamedTargets = targetsNamedKeyInDepProduct.compactMap{ $0.moduleAliases }.flatMap{$0}
                                if aliasesInDepProductForKeyNamedTargets.isEmpty {
                                    // This check is added out of precaution but
                                    // shouldn't be needed
                                    if targetToResolve.moduleAliases?[key] != nil {
                                        targetToResolve.removeModuleAlias(for: key)
                                    }
                                } else {
                                    // There should be only one alias to apply
                                    for entry in aliasesInDepProductForKeyNamedTargets {
                                        targetToResolve.addModuleAlias(for: entry.key, as: entry.value)
                                        let prechain = lookupAlias(value: entry.value, in: aliasBuffer).filter { $0 != entry.key }
                                        if let prechainKey = prechain.first {
                                            aliasBuffer.removeValue(forKey: prechainKey)
                                        }
                                    }
                                }
                            } else {
                                for alias in aliases {
                                    let prechain = lookupAlias(value: alias, in: aliasBuffer).filter { $0 != key }
                                    if let prechainKey = prechain.first {
                                        // Add a prechain alias
                                        if let existing = targetToResolve.moduleAliases?[prechainKey],
                                           existing != alias {
                                            targetToResolve.removeModuleAlias(for: prechainKey)
                                        } else {
                                            observabilityScope.emit(info: "Multiple module aliases \(aliases.sorted()) found for '\(targetToResolve.name)'; when referencing them in source code from target '\(targetToResolve.name)' or its depending targets, use the aliased names directly instead of the original name")
                                            targetToResolve.addModuleAlias(for: prechainKey, as: alias)
                                            aliasBuffer.removeValue(forKey: prechainKey)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // This fills in aliases for targets in products that are in the dependency chain
    // but not in a product consumed by other packages. Such targets still need to have
    // aliases applied to them so they can be built with correct dependent binary names
    func fillInRest(package: PackageIdentity) {
        if let productToTargets = idToProductToAllTargets[package] {
            for (_, productTargets) in productToTargets {
                let unAliased = productTargets.contains{$0.moduleAliases == nil}
                if unAliased {
                    for target in productTargets {
                        let depAliases = target.dependentTargets().compactMap{$0.moduleAliases}.flatMap{$0}
                        for (key, alias) in depAliases {
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

    private func lookupAlias(key: String, in buffer: [String: ModuleAliasModel]) -> String? {
        var next = key
        while let nextValue = buffer[next] {
            next = nextValue.alias
        }
        return next == key ? nil : next
    }

    private func lookupAlias(value: String, in buffer: [String: ModuleAliasModel]) -> [String] {
        let keys = buffer.filter{$0.value.alias == value}.map{$0.key}
        return keys
    }
}

// Used to keep track of module alias info for each package
class ModuleAliasModel {
    let name: String
    var alias: String
    let originPackage: PackageIdentity
    let consumingPackage: PackageIdentity

    init(name: String, alias: String, originPackage: PackageIdentity, consumingPackage: PackageIdentity) {
        self.name = name
        self.alias = alias
        self.originPackage = originPackage
        self.consumingPackage = consumingPackage
    }
}

extension Target {
    func dependsOn(productID: String) -> Bool {
        return dependencies.contains { dep in
            if case let .product(prodRef, _) = dep {
                return prodRef.ID == productID
            }
            return false
        }
    }

    func dependentTargets() -> [Target] {
        return dependencies.compactMap{$0.target}
    }
}
