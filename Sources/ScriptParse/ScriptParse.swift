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
import ArgumentParser

public struct ScriptParse: ParsableCommand {
    @Argument var file: String

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()
    
    public init() {}
}

extension ScriptParse {
    static func parse(_ path: AbsolutePath) throws -> ScriptDependencies {
        let syntaxTree = try SyntaxParser.parse(path.asURL)
//        let converter = SourceLocationConverter(file: path.basename, tree: syntaxTree)

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
                if let _path = try parseStringArgument(&tokens, label: "path"),
                   case let path = AbsolutePath(_path, relativeTo: path.parentDirectory) {
                    let name = try parseStringArgument(&tokens, label: "name")
                    collected.append(PackageDependency(of: PackageModel(desc.replacingOccurrences(of: _path, with: path.pathString), path: path, name: name)))
                } else if let _url = try parseStringArgument(&tokens, label: "url"),
                          let url = URL(string: _url) {
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
        return ScriptDependencies(sourceFile: path, modules: collected)
    }
    
    public func run() throws {
        let path = try AbsolutePath(validating: file)
        let json = try ScriptParse.manifest(for: path)
        print(String(data: json, encoding: .utf8)!)
    }
    
    // FIXME: This should be removed some day.
    public static func manifest(for path: AbsolutePath) throws -> Data {
        let output = try parse(path)
        let json = try encoder.encode(output)
        return json
    }
}
