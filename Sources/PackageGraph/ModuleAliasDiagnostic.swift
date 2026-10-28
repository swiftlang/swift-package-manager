//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel

/// Every diagnostic that the module alias tracker emits.
enum ModuleAliasDiagnostic {
    /// An alias in a chain is overridden by the alias that terminates the chain.
    case aliasOverridden(
        alias: String,
        declaringPackage: PackageIdentity,
        declaringModule: String,
        product: String,
        overriddenBy: String
    )
    /// A module could not apply an alias to a name, so it has to use the aliased names directly in its source.
    case useAliasedNamesDirectly(module: String, name: String, aliasedNames: [String])
    /// A module that is aliased may contain non-Swift sources, whose symbols are not renamed.
    case nonSwiftSources(module: String, product: String, package: PackageIdentity, aliases: [String: String])
    /// A declared alias that did not match any recursive dependency of the product it was declared for.
    case unmatchedAlias(module: String, declaringPackage: PackageIdentity, product: String, package: PackageIdentity)

    var message: String {
        switch self {
        case .aliasOverridden(let alias, let declaringPackage, let declaringModule, let product, let overriddenBy):
            return "Module alias '\(alias)' defined in package '\(declaringPackage)' for target '\(declaringModule)' in package/product '\(product)' is overridden by alias '\(overriddenBy)'; if this override is not intended, remove '\(overriddenBy)' from 'moduleAliases' in its manifest"
        case .useAliasedNamesDirectly(let module, let name, let aliasedNames):
            let names = aliasedNames.map { "'\($0)'" }.joined(separator: ", ")
            return "Target '\(module)' has a dependency on multiple targets named '\(name)'; the aliased names are [\(names)] and should be used directly in source code if referenced from '\(module)'"
        case .nonSwiftSources(let module, let product, let package, let aliases):
            let aliasesMsg = aliases.sorted { $0.key < $1.key }.map { "'\($0.key)' as '\($0.value)'" }.joined(separator: ", ")
            return "target '\(module)' for product '\(product)' from package '\(package)' has module aliases: [\(aliasesMsg)] but may contain non-Swift sources; there might be a conflict among non-Swift symbols"
        case .unmatchedAlias(let module, let declaringPackage, let product, let package):
            return "module alias for target '\(module)', declared in package '\(declaringPackage)', does not match any recursive target dependency of product '\(product)' from package '\(package.description)'"
        }
    }
}

extension ObservabilityScope {
    func emit(_ diagnostic: ModuleAliasDiagnostic) {
        switch diagnostic {
        case .aliasOverridden, .useAliasedNamesDirectly:
            self.emit(info: diagnostic.message)
        case .nonSwiftSources, .unmatchedAlias:
            self.emit(warning: diagnostic.message)
        }
    }
}
