/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

extension Package {
    func products(_ allModules: [Module]) throws -> [Product] {

        var products = [Product]()

        let testModules: [TestModule]
        let modules: [Module]
        (testModules, modules) = allModules.partition()

    ////// first auto-determine executables

        for case let module as SwiftModule in modules {
            if module.type == .Executable {
                let product = Product(name: module.name, type: .Executable, modules: [module])
                products.append(product)
            }
        }

    ////// auto-determine tests

        if !testModules.isEmpty {
            let modules: [SwiftModule] = testModules.map{$0} // or linux compiler crash (2016-02-03)
            //TODO and then we should prefix all modules with their package probably
            //Suffix 'Tests' to test product so the module name of linux executable don't collide with
            //main package, if present.
            let product = Product(name: "\(self.name)Tests", type: .Test, modules: modules)
            products.append(product)
        }

    ////// add products from the manifest

        for p in manifest.products {
            let modules: [SwiftModule] = p.modules.flatMap{ moduleName in
                guard case let picked as SwiftModule = (modules.pick{ $0.name == moduleName }) else {
                    print("warning: No module \(moduleName) found for product \(p.name)")
                    return nil
                }
                return picked
            }

            guard !modules.isEmpty else {
                throw Product.Error.NoModules(p.name)
            }

            let product = Product(name: p.name, type: p.type, modules: modules)
            products.append(product)
        }

        return products
    }
}
