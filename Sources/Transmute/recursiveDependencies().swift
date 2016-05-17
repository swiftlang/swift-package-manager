/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class PackageType.Module
import protocol PackageType.ModuleTypeProtocol

public func recursiveDependencies(_ modules: [Module]) throws -> [Module] {
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

            throw Module.Error.DuplicateModule(top.name)
        }
    }

    return rv
}
