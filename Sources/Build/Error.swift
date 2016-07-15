/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import protocol Basic.FixableError
import struct PackageModel.Manifest

public enum Error: Swift.Error {
    case noModules
    case onlyCModule(name: String)
}

extension Error: FixableError {
    public var error: String {
        switch self {
        case .noModules:
            return "no modules found"
        case .onlyCModule(let name):
            return "only system module package \(name) found"
        }
    }

    public var fix: String? {
        switch self {
            case .noModules:
                return "define a module inside \(Manifest.filename)"
            case .onlyCModule:
                return "to use this system module package, include it in another project"
        }
    }
}
