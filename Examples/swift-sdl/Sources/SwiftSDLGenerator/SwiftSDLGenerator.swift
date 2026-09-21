//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import SwiftSyntax
import SwiftParser
#if canImport(System)
import System
#else
import SystemPackage
#endif

@main
struct SwiftSDLGenerator {

    static func main() async throws {
        let moduleMap = """
        module SwiftSDL3 [system] {
            header "SDL.h"
            export *
        }
        """
        let moduleMapFile = FilePath(CommandLine.arguments[1])
        FileManager.default.createFile(atPath: moduleMapFile.string, contents: moduleMap.data(using: .utf8))

        let header = """
        #define SDL_MAIN_USE_CALLBACKS 1
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_main.h>
        """
        let headerFile = FilePath(CommandLine.arguments[2])
        FileManager.default.createFile(atPath: headerFile.string, contents: header.data(using: .utf8))

        // Remove api notes file before we parse the swift interface
        let apiNotesFile = moduleMapFile.removingLastComponent().appending("SwiftSDL3.apinotes")
        if FileManager.default.fileExists(atPath: apiNotesFile.string) {
            try FileManager.default.removeItem(atPath: apiNotesFile.string)
        }

        // Exercize the AST code
        let headerPaths = [FilePath(CommandLine.arguments[4])]
        let ast = try await loadAST(headerPaths: headerPaths, headerFile: headerFile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let astData = try encoder.encode(ast)
        let astFile = headerFile.removingLastComponent().appending("ast.json")
        FileManager.default.createFile(atPath: astFile.string, contents: astData)

        let astFunctions: [String: ASTFunction] = .init(ast.inner?.compactMap({ item in
            guard item.kind == "FunctionDecl",
                let name = item.name,
                let type = item.type?.qualType,
                let match = type.firstMatch(of: #/^([^(]+)/#)
            else {
                return nil
            }
            
            let parameters: [String: String] = .init(item.inner?.compactMap({ param -> (String, String)? in
                guard param.kind == "ParmVarDecl",
                    let name = param.name,
                    let type = param.type?.qualType
                else {
                    return nil
                }
                return (name, type)
            }) ?? [], uniquingKeysWith: { $1 })
            
            return (name, ASTFunction(
                returnType: String(match.1),
                parameters: parameters
            ))
        }) ?? [], uniquingKeysWith: { $1 })
        let astFunctionsFile = headerFile.removingLastComponent().appending("astFunctions.txt")
        FileManager.default.createFile(atPath: astFunctionsFile.string, contents: try encoder.encode(astFunctions))

        // Exercise the parsing of the swiftinterface
        let sourceFileSyntax = try await parseInterface(
            headerPaths: headerPaths,
            moduleDir: moduleMapFile.removingLastComponent(),
            moduleName: "SwiftSDL3"
        )
        let syntaxText = String(describing: sourceFileSyntax)
        let syntaxFile = headerFile.removingLastComponent().appending("syntax.txt")
        FileManager.default.createFile(atPath: syntaxFile.string, contents: syntaxText.data(using: .utf8))

        var usedTypes: Set<String> = []

        let functions = sourceFileSyntax.statements.compactMap { item -> CodeBlockItemSyntax? in
            guard let function = item.item.as(FunctionDeclSyntax.self),
                let astFunction = astFunctions[function.name.text]
            else {
                return nil
            }

            var signature = function.signature
            var changed = false
            var count = 0

            let parameters = function.signature.parameterClause.parameters.map { parameter -> (FunctionParameterSyntax, LabeledExprSyntax) in
                let name = parameter.secondName ?? parameter.firstName
                let newParameter: FunctionParameterSyntax
                var expression: LabeledExprSyntax
                if isOpaquePointerIUO(parameter.type),
                    let astType = astFunction.parameters[name.text],
                    astType.hasSuffix(" *")
                {
                    let type = String(astType.dropLast(2))
                    usedTypes.insert(type)
                    changed = true

                    newParameter = parameter.with(\.type,
                        TypeSyntax(IdentifierTypeSyntax(name: .identifier(type)))
                    )
                    expression = LabeledExprSyntax(
                        expression: MemberAccessExprSyntax(
                            base: DeclReferenceExprSyntax(baseName: name),
                            declName: DeclReferenceExprSyntax(baseName: .identifier("pointer"))
                        )
                    )
                } else {
                    newParameter = parameter
                    expression = LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: name)))
                }

                if count < function.signature.parameterClause.parameters.count - 1 {
                    expression = expression.with(\.trailingComma, .commaToken(trailingTrivia: .space))
                }
                count += 1

                return (newParameter, expression)
            }

            var functionCall = FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_" + function.name.text)),
                leftParen: .leftParenToken(),
                arguments: .init(parameters.map(\.1)),
                rightParen: .rightParenToken(),
            )

            if let returnClause = function.signature.returnClause,
                isOpaquePointerIUO(returnClause.type),
                astFunction.returnType.hasSuffix(" *")
            {
                let returnType = String(astFunction.returnType.dropLast(2))
                usedTypes.insert(returnType)
                changed = true

                signature = signature.with(\.returnClause,
                    returnClause.with(\.type,
                        TypeSyntax(IdentifierTypeSyntax(name: .identifier(returnType)))
                    )
                )

                functionCall = FunctionCallExprSyntax(
                    calledExpression: DeclReferenceExprSyntax(baseName: .identifier(returnType)),
                    leftParen: .leftParenToken(),
                    arguments: .init([.init(expression: functionCall)]),
                    rightParen: .rightParenToken()
                )
            }

            guard changed else {
                return nil
            }

            signature = signature.with(\.parameterClause,
                signature.parameterClause.with(\.parameters, .init(parameters.map(\.0)))
            )

            functionCall = functionCall.with(\.leadingTrivia,
                .init(pieces: [.newlines(1), .spaces(4)])
            ).with(\.trailingTrivia, .newline)

            return CodeBlockItemSyntax(item: .decl(.init(
                function.with(\.signature, signature)
                    .with(\.body, CodeBlockSyntax(
                        leadingTrivia: .space,
                        statements: .init([CodeBlockItemSyntax(item: .init(functionCall))]))
                    )
                )
            ))
        }

        let opaquesFile = headerFile.removingLastComponent().appending("opaques.txt")
        let newSourceFile = SourceFileSyntax(statements: .init(functions))
        FileManager.default.createFile(atPath: opaquesFile.string, contents: newSourceFile.description.data(using: .utf8))

        // TODO: Generate an API header to help with the Swift bindings
        let apiNotes = """
        Name: SwiftSDL3
        Functions:
        - Name: SDL_GetVersion
          SwiftName: SwiftSDL_GetVersion()
        """
        FileManager.default.createFile(atPath: apiNotesFile.string, contents: apiNotes.data(using: .utf8))

        // TODO: Generate Swift bindings to make the Swift interface more ergonomic.
        // This includes replacing occurences of OpaquePointer with a more type safe alternative
        // by parsing the interfaces that use opaque structs and create replacements.
        let bindings = """
        """
        let bindingsFile = FilePath(CommandLine.arguments[3])
        FileManager.default.createFile(atPath: bindingsFile.string, contents: bindings.data(using: .utf8))
    }
}

func isOpaquePointerIUO(_ type: TypeSyntax) -> Bool {
    guard let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) else {
        return false
    }

    return iuo.wrappedType.as(IdentifierTypeSyntax.self)?.name.text == "OpaquePointer"
}

struct ASTFunction: Codable {
    let returnType: String
    let parameters: [String: String] // name to type
}
