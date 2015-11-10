/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/**
 A Target is a collection of sources and configuration that can be built
 into a product.
*/
public class Target {
    public let sources: [String]
    public let type: TargetType
    public let productName: String
    public let moduleName: String
    public var dependencies: [Target]  /// in build order

    init(productName: String, sources: [String], type: TargetType) throws {
        self.productName = productName
        self.sources = sources
        self.type = type
        self.dependencies = []
        do {
            moduleName = try moduleNameForName(productName)
        } catch {
            moduleName = ""
            throw error
        }
    }
}

public enum TargetType {
    case Executable
    case Library
}

extension TargetType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Executable:
            return "Executable"
        case .Library:
            return "Library"
        }
    }
}
