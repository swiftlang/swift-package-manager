/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_exported import enum PackageDescription.ProductType
import Utility

public class Product {
    public let name: String
    public let type: ProductType
    public let modules: [Module]

    public init(name: String, type: ProductType, modules: [Module]) {
        self.name = name
        self.type = type
        self.modules = modules
    }

    public var outname: String {
        switch type {
        case .Executable:
            return name
        case .Library(.Static):
            return "lib\(name).a"
        case .Library(.Dynamic):
            return name.soname
        case .Test:
            let base = "\(name).xctest"
            #if os(OSX)
                return "\(base)/Contents/MacOS/\(name)"
            #else
                return base
            #endif
        }
    }
}

public enum LibraryType {
    case dynamic
    case Static
}

extension Product: CustomStringConvertible {
    public var description: String {
        let base = outname.basename
        switch type {
        case .Test:
            return "\(base).xctest"
        default:
            return base
        }
    }
}
