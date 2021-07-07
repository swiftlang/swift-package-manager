/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 FIXME: This is a temporary alternative of the frontend implementation.
*/

import SwiftSyntax
import TSCBasic
import Foundation

guard CommandLine.argc > 1 else {
    throw ScriptParseError.noFileSpecified
}

let path = try AbsolutePath(validating: CommandLine.arguments[1])
let syntaxTree = try SyntaxParser.parse(path.asURL)
let converter = SourceLocationConverter(file: path.basename, tree: syntaxTree)

var inPackageScope = false
var keyStatements: [CodeBlockItemSyntax] = []
for statement in syntaxTree.statements {
    if statement.statementKind == .import && inPackageScope {
        keyStatements.append(statement)
    } else {
        inPackageScope = false
    }
    if statement.statementKind == .package
        && statement.nextToken?.tokenKind == .importKeyword {
        inPackageScope = true
        keyStatements.append(statement)
    }
}

var collected: [PackageDependency] = []

try keyStatements.forEach {
    switch $0.statementKind {
    case .package:
        var tokens = [TokenSyntax]($0.tokens.dropFirst(2))
        guard tokens.first?.tokenKind == .leftParen,
              tokens.last?.tokenKind == .rightParen else {
                  throw ScriptParseError.wrongSyntax
              }
        tokens.removeFirst()
        tokens.removeLast()
        let desc = tokens.map(\.text).joined()
        // parse the first argument
        if let path = try parseStringArgument(&tokens, label: "path") {
            collected.append(PackageDependency(of: PackageModel(desc, path: path)))
        } else if let url = try parseStringArgument(&tokens, label: "url") {
            collected.append(PackageDependency(of: PackageModel(desc, url: url)))
        }
        // TODO: other parsing
        else {
            collected.append(PackageDependency(of: PackageModel(desc)))
        }

    case .import:
        let tokens = [TokenSyntax]($0.tokens.dropFirst())
        guard tokens.count == 1,
              let moduleToken = tokens.first,
              case .identifier(let moduleName) = moduleToken.tokenKind
        else { throw ScriptParseError.unsupportedSyntax }
        var model = collected.removeLast()
        model.modules.append(moduleName)
        collected.append(model)

    default:
        fatalError()
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted

let json = try encoder.encode(ScriptDependencies(sourceFile: path, modules: collected))
print(String(data: json, encoding: .utf8)!)
