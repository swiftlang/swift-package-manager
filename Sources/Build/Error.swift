/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorProtocol {
    case noModules
    case noProducts
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules:
            return "no modules found"
        case .noProducts:
            return "no products found (note: modulemaps cannot be build)"
        }
    }
}
