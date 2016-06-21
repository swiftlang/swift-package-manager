/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Utility

import func POSIX.exit

/// Load packages into a complete set of modules and products.
public func transmute(_ rootPackage: Package, externalPackages: [Package]) throws -> (modules: [Module], externalModules: [Module], products: [Product]) {
    var products: [Product] = []
    var map: [Package: [Module]] = [:]
    
    let packages = externalPackages + [rootPackage]

    for package in packages {

        var modules: [Module]
        do {
            modules = try package.modules()
        } catch ModuleError.noModules(let pkg) where pkg === rootPackage {
            //Ignore and print warning if root package doesn't contain any sources
            print("warning: root package '\(pkg)' does not contain any sources")
            if packages.count == 1 { exit(0) } //Exit now if there is no more packages 
            modules = []
        }

        if package == rootPackage {
            //TODO allow testing of external package tests

            let testModules = try package.testModules()

            // Set dependencies for test modules.
            for case let testModule as SwiftModule in testModules {
                if testModule.basename == "Utility" {
                    // FIXME: The Utility tests currently have a layering
                    // violation and a dependency on Basic for infrastructure.
                    testModule.dependencies = modules.filter{
                        switch $0.name {
                        case "Basic", "Utility":
                            return true
                        default:
                            return false
                        }
                    }
                } else if testModule.basename == "Functional" {
                    // FIXME: swiftpm's own Functional tests module does not
                    //        follow the normal rules--there is no corresponding
                    //        'Sources/Functional' module to depend upon. For the
                    //        time being, assume test modules named 'Functional'
                    //        depend upon 'Utility', and hope that no users define
                    //        test modules named 'Functional'.
                    testModule.dependencies = modules.filter{
                        switch $0.name {
                        case "Basic", "Utility", "PackageModel":
                            return true
                        default:
                            return false
                        }
                    }
                } else if testModule.basename == "PackageLoading" {
                    // FIXME: Turns out PackageLoadingTests violate encapsulation :(
                    testModule.dependencies = modules.filter{
                        switch $0.name {
                        case "Get", "PackageLoading":
                            return true
                        default:
                            return false
                        }
                    }
                } else {
                    // Normally, test modules are only dependent upon modules with
                    // the same basename. For example, a test module in
                    // 'Root/Tests/Foo' is dependent upon 'Root/Sources/Foo'.
                    testModule.dependencies = modules.filter{ $0.name == testModule.basename }
                }

                modules += testModules.map{$0}
            }
        }

        map[package] = modules
        products += try package.products(modules)
    }

    // ensure modules depend on the modules of any dependent packages
    fillModuleGraph(packages, modulesForPackage: { map[$0]! })

    let modules = try PackageLoading.recursiveDependencies(packages.flatMap{ map[$0] ?? [] })
    let externalModules = try PackageLoading.recursiveDependencies(externalPackages.flatMap{ map[$0] ?? [] })

    return (modules, externalModules, products)
}

private func fillModuleGraph(_ packages: [Package], modulesForPackage: (Package) -> [Module]) {
    for package in packages {
        let packageModules = modulesForPackage(package)
        for dep in package.recursiveDependencies {
            let depModules = modulesForPackage(dep).filter{
                guard !$0.isTest else { return false }

                switch $0 {
                case let module as SwiftModule where module.type == .library:
                    return true
                case is CModule:
                    return true
                default:
                    return false
                }
            }
            for module in packageModules {
                module.dependencies.insert(contentsOf: depModules, at: 0)
            }
        }
    }
}

extension Package {
    private var recursiveDependencies: [Package] {
        // FIXME: Refactor this to a common algorithm.
        var set = Set<Package>()
        var stack = dependencies
        var out = [Package]()

        while !stack.isEmpty {
            let target = stack.removeFirst()
            if !set.contains(target) {
                set.insert(target)
                stack += target.dependencies
                out.append(target)
            }
        }

        return out
    }
}

private func recursiveDependencies(_ modules: [Module]) throws -> [Module] {
    // FIXME: Refactor this to a common algorithm.
    var stack = modules
    var set = Set<Module>()
    var rv = [Module]()

    while stack.count > 0 {
        let top = stack.removeFirst()
        if !set.contains(top) {
            rv.append(top)
            set.insert(top)
            stack += top.dependencies
        } else {
            guard let index = set.index(of: top),
                  let moduleInSet = set[index] as? ModuleTypeProtocol,
                  let module = top as? ModuleTypeProtocol
                      where module.sources.root != moduleInSet.sources.root else {
                continue;
            }

            throw Module.Error.duplicateModule(top.name)
        }
    }

    return rv
}
