/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorProtocol {
    case noModules
    case cModule(name: String)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules:
            return "no modules found."
        case .cModule(let name):
            return "system module package \(name) found. To use this system module package, include it in another project."
        }
    }
}
