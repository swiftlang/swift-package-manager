/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel

extension Package {
    public enum ModuleError: ErrorProtocol {
        case NoModules(Package)
        case ModuleNotFound(String)
        case InvalidLayout(InvalidLayoutType)
        case ExecutableAsDependency(String)
    }

    public enum InvalidLayoutType {
        case MultipleSourceRoots([String])
        case InvalidLayout([String])
    }
}

extension Package.InvalidLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .MultipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.joined(separator: ", ")
        case .InvalidLayout(let paths):
            return "unexpected source file(s) found: " + paths.joined(separator: ", ")
        }
    }
}


extension Module {
    public enum Error: ErrorProtocol {
        case NoSources(String)
        case MixedSources(String)
        case DuplicateModule(String)
    }
}

extension Product {
    public enum Error: ErrorProtocol {
        case NoModules(String)
    }
}
