/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

public func transmute(packages: [Package]) throws -> ([Module], [Product]) {

    var products: [Product] = []
    var map: [Package: [Module]] = [:]

    for package in packages {
        let modules = try package.modules()
        let testModules = try package.testModules()
        products += try package.products(modules, tests: testModules)

        // Set dependencies for test modules.
        for testModule in testModules {
            if testModule.basename == "Functional" {
                // FIXME: swiftpm's own Functional tests module does not
                //        follow the normal rules--there is no corresponding
                //        'Sources/Functional' module to depend upon. For the
                //        time being, assume test modules named 'Functional'
                //        depend upon 'Utility', and hope that no users define
                //        test modules named 'Functional'.
                testModule.dependencies = modules.filter{ $0.name == "Utility" }
            }
            else if testModule.basename == "Transmute" {
                // FIXME: Turns out TransmuteTests violate encapsulation :(
                testModule.dependencies = modules.filter{ $0.name == "Get" || $0.name == "Transmute" }
            }
            else {
                // Normally, test modules are only dependent upon modules with
                // the same basename. For example, a test module in
                // 'Root/Tests/Foo' is dependent upon 'Root/Sources/Foo'.
                testModule.dependencies = modules.filter{ $0.name == testModule.basename }
            }
        }

        map[package] = modules + testModules.map{$0}
    }

    // ensure modules depend on the modules of any dependent packages
    fillModuleGraph(packages, modulesForPackage: { map[$0]! })

    var set = Set<Module>()
    var stack = packages.flatMap{ map[$0] ?? [] }
    var modules = [Module]()

    while !stack.isEmpty {
        let module = stack.removeFirst()
        if !set.contains(module) {
            set.insert(module)
            stack += module.dependencies
            modules.append(module)
        }
    }

    return (modules, products)
}
