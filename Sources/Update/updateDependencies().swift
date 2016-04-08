/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType


public struct DependencyGraphDelta {
    var created: [Package] = []
    var deleted: [Package] = []
    var updated: [Package] = []
    var thesame: [Package] = []
}


enum Error: ErrorProtocol {
    case UnresolvableGraph
}


public func calculateUpdatedDependencyGraph(manifest: Manifest, packages: [Package]) throws -> DependencyGraphDelta {

    for pkg in packages {
        try pkg.fetch()
    }

    

    return DependencyGraphDelta()
}


public func updateDependencies(manifest manifest: Manifest) throws {

}


extension Package {
    func fetch() throws {}
}
