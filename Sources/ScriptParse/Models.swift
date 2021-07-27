/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 FIXME: This is a temporary alternative of the frontend implementation.
*/

import struct Foundation.URL
import TSCBasic
import SwiftSyntax

struct PackageModel: Codable {
    let raw: String
    let path: AbsolutePath?
    let url: URL?
    let name: String?

    init(_ raw: String, path: AbsolutePath? = nil, url: URL? = nil, name: String? = nil) {
        self.raw = raw
        self.path = path
        self.url = url
        self.name = name
    }
}

struct PackageDependency: Codable {
    let package: PackageModel
    var modules: [String] = []
    
    init(of package: PackageModel) {
        self.package = package
    }
}

struct ScriptDependencies: Codable {
    let sourceFile: AbsolutePath
    let modules: [PackageDependency]
}

enum ScriptParseError: Swift.Error, CustomStringConvertible {
    case wrongSyntax
    case unsupportedSyntax
    case noFileSpecified

    var description: String {
        switch self {
        case .wrongSyntax:
            return "Syntax error"
        case .unsupportedSyntax:
            return "Unsupported import syntax"
        case .noFileSpecified:
            return "Please specify a file"
        }
    }
}
