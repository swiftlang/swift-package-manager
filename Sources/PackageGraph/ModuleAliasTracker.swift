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
        var allTargetDeps = product.targets.map{$0.recurisveDependentTargets().map{$0.dependencies}}.flatMap{$0}.flatMap{$0}
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
    func propagate(productID: String,
                   observabilityScope: ObservabilityScope,
                   aliasBuffer: inout [String: ModuleAliasModel]) {
        let productAliases = aliasMap[productID] ?? []
        for aliasModel in productAliases {
            // Alias buffer is used to carry down aliases defined upstream
            if let existing = aliasBuffer[aliasModel.name],
               existing.alias != aliasModel.alias {
                observabilityScope.emit(info: "Alias '\(aliasModel.alias)' for '\(aliasModel.name)' defined in '\(productID)' is overridden by '\(existing.alias)'; if this is not intended, remove the latter from 'moduleAliases' in its manifest")
            } else {
                aliasBuffer[aliasModel.name] = aliasModel
            }
        }

        if let curDirectTargets = productToDirectTargets[productID] {
            var relevantTargets = curDirectTargets.map{$0.recurisveDependentTargets()}.flatMap{$0}
            relevantTargets.append(contentsOf: curDirectTargets)

            for relTarget in relevantTargets {
                if let val = lookupAlias(key: relTarget.name, in: aliasBuffer) {
                    relTarget.addModuleAlias(for: relTarget.name, as: val)
                    if let prechainVal = aliasBuffer[relTarget.name],
                       prechainVal.alias != val {
                        relTarget.addPrechainModuleAlias(for: relTarget.name, as: prechainVal.alias)
                        relTarget.addPrechainModuleAlias(for: prechainVal.alias, as: val)
                        aliasBuffer.removeValue(forKey: prechainVal.alias)
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
    func merge(productID: String,
               observabilityScope: ObservabilityScope) {
        guard let children = parentToChildProducts[productID] else {
            return
        }
        for childID in children {
            merge(productID: childID,
                  observabilityScope: observabilityScope)
        }

        if let curDirectTargets = productToDirectTargets[productID] {
            let depTargets = curDirectTargets.map{$0.recurisveDependentTargets()}.flatMap{$0}
            let depTargetAliases = toDictionary(depTargets.compactMap{$0.moduleAliases})
            let depChildTargets = depTargets.map{$0.dependencies.compactMap{$0.product?.ID}}.flatMap{$0}.compactMap{productToAllTargets[$0]}.flatMap{$0}
            let depChildAliases = toDictionary(depChildTargets.compactMap{$0.moduleAliases})
            let depChildPrechainAliases = toDictionary(depChildTargets.compactMap{$0.prechainModuleAliases})
            chainModuleAliases(targets: depTargets,
                               checkedTargets: depTargets,
                               targetAliases: depTargetAliases,
                               childTargets: depChildTargets,
                               childAliases: depChildAliases,
                               childPrechainAliases: depChildPrechainAliases)

            let relevantTargets = depTargets + curDirectTargets
            let targetAliases = toDictionary(relevantTargets.compactMap{$0.moduleAliases})
            let depProductTargets = relevantTargets.map{$0.dependencies.compactMap{$0.product?.ID}}.flatMap{$0}.compactMap{productToAllTargets[$0]}.flatMap{$0}
            var depProductAliases = [String: [String]]()
            let depProductPrechainAliases = toDictionary(depProductTargets.compactMap{$0.prechainModuleAliases})
            for depProdTarget in depProductTargets {
                let depProdTargetAliases = depProdTarget.moduleAliases ?? [:]
                for (key, val) in depProdTargetAliases {
                    var shouldAdd = false
                    if depProdTarget.name == key {
                        shouldAdd = true
                    } else if !depProductTargets.map({$0.name}).contains(key) {
                        shouldAdd = true
                    }
                    if shouldAdd {
                        if depProductAliases[key]?.contains(val) ?? false {
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
                               childPrechainAliases: depProductPrechainAliases)
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
                        let depAliases = target.recurisveDependentTargets().compactMap{$0.moduleAliases}.flatMap{$0}
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

    private func lookupAlias(value: String, in dict: [String: [String]]) -> [String] {
        let keys = dict.filter{$0.value.contains(value)}.map{$0.key}
        return keys
    }

    private func toDictionary(_ list: [[String: String]]) -> [String: [String]] {
        var dict = [String: [String]]()
        for entry in list {
            for (entryKey, entryVal) in entry {
                if let existing = dict[entryKey], existing.contains(entryVal) {
                    // don't do anything
                } else {
                    dict[entryKey, default: []].append(entryVal)
                }
            }
        }
        return dict
    }

    private func chainModuleAliases(targets: [Target],
                                    checkedTargets: [Target],
                                    targetAliases: [String: [String]],
                                    childTargets: [Target],
                                    childAliases: [String: [String]],
                                    childPrechainAliases: [String: [String]]) {
        var aliasDict = [String: String]()
        var prechainAliasDict = [String: String]()
        for (childTargetName, childTargetAliases) in childAliases {
            // Tracks whether to add prechain aliases to targets
            var addPrechain = false
            // Current targets and their dependents contain this child target name
            if checkedTargets.map({$0.name}).contains(childTargetName) {
                addPrechain = true
            }
            if let overlappingTargetAliases = targetAliases[childTargetName], !overlappingTargetAliases.isEmpty {
                // Current target aliases have the same key as this child target name,
                // so the child target alias should not be applied
                addPrechain = true
                aliasDict[childTargetName] = overlappingTargetAliases.first
            } else if childTargetAliases.count > 1 {
                // Multiple aliases from different products for this child target name
                // so they should not be applied; their aliases (new names) should be
                // used directly
                addPrechain = true
            } else if childTargets.filter({$0.name == childTargetName}).count > 1 {
                // Targets from different products have the same name as this child
                // target name, so their aliases should not be applied
                addPrechain = true
            }

            if addPrechain {
                if let prechainAliases = childPrechainAliases[childTargetName],
                   let prechainAlias = prechainAliases.first {
                    prechainAliasDict[prechainAlias] = childPrechainAliases[prechainAlias]?.first
                } // else just use the renamed module directly
            } else if let productTargetAlias = childTargetAliases.first {
                // there should be one element
                aliasDict[childTargetName] = productTargetAlias
            }
        }

        for target in targets {
            for (key, val) in aliasDict {
                target.addModuleAlias(for: key, as: val)
            }
            for (key, val) in prechainAliasDict {
                target.addModuleAlias(for: key, as: val)
                target.addPrechainModuleAlias(for: key, as: val)
            }
        }
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

    func recurisveDependentTargets() -> [Target] {
        var list = [Target]()
        var nextDeps = dependencies
        while !nextDeps.isEmpty {
            let nextTargets = nextDeps.compactMap{$0.target}
            list.append(contentsOf: nextTargets)
            nextDeps = nextTargets.map{$0.dependencies}.flatMap{$0}
        }
        return list
    }
}
