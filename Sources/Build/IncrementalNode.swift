/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import PackageType

struct IncrementalNode {
    let module: SwiftModule
    let prefix: String

    var tempsPath: String {
        return Path.join(prefix, "\(module.c99name).build")
    }

    var swiftModuleName: String {
        return "\(module.c99name).swiftmodule"
    }

    var objectPaths: [String] {
        return module.sources.relativePaths.map{ Path.join(tempsPath, "\($0).o") }
    }

    var outputs: [String] {
        return [module.targetName] + objectPaths
    }

    var inputs: [String] {
        return module.recursiveDependencies.map{ $0.targetName }
    }

    var moduleOutputPath: String {
        return Path.join(prefix, swiftModuleName)
    }
}
