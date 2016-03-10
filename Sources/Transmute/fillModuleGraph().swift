/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType

func fillModuleGraph(packages: [Package], modulesForPackage: (Package) -> [Module]) {
    for package in packages {
        let packageModules = modulesForPackage(package)
        for dep in package.recursiveDependencies {
            let depModules = modulesForPackage(dep).filter{
                switch $0 {
                case is TestModule:
                    return false
                case let module as SwiftModule where module.type == .Library:
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
