/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType

/**
 Depth-first topological sort of target dependencies.
 */
func sort(module: Module) {
    var visited = Set<Module>()

    func recurse(module: Module) -> [Module] {
        return module.dependencies.flatMap { dep -> [Module] in
            if visited.contains(dep) {
                return []
            } else {
                visited.insert(dep)
                return recurse(dep) + [dep]
            }
        }
    }

    module.dependencies = recurse(module).reversed()
}
