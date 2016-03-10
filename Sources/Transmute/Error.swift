/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType

extension Package {
    public enum ModuleError: ErrorProtocol {
        case NoModules(Package)
        case ModuleNotFound(String)
        case InvalidLayout(InvalidLayoutType)
    }

    public enum InvalidLayoutType {
        case MultipleSourceRoots([String])
        case InvalidLayout
    }
}

extension Module {
    public enum Error: ErrorProtocol {
        case NoSources(String)
    }
}
