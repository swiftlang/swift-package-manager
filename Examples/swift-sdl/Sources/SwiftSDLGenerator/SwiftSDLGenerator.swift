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
import ArgumentParser
import SwiftSyntax
import SwiftParser
#if canImport(System)
import System
#else
import SystemPackage
#endif

@main
struct SwiftSDLGenerator: AsyncParsableCommand {
    @Option(help: "The SDK to use when running the Swift interface generator")
    var sdk: FilePath

    @Option(help: "The triple")
    var triple: String

    @Option(help: "swift resource dir")
    var swiftResourceDir: FilePath

    @Option(help: "clang resource dir")
    var clangResourceDir: FilePath

    @Option(help: "Generated modulemap file")
    var modulemapFile: FilePath

    @Option(help: "Generated header file")
    var headerFile: FilePath

    @Option(help: "Generated bindings file")
    var bindingsFile: FilePath

    @Option(help: "Generated API notes file")
    var apinotesFile: FilePath

    @Option(help: "Header paths for SDL")
    var headerPath: [FilePath]

    func run() async throws {
        let moduleMap = """
        module SwiftSDL3 [system] {
            header "SDL.h"
            export *
        }
        """
        FileManager.default.createFile(atPath: modulemapFile.string, contents: moduleMap.data(using: .utf8))

        let header = """
        #define SDL_MAIN_USE_CALLBACKS 1
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_main.h>
        #include <stddef.h>
        """
        FileManager.default.createFile(atPath: headerFile.string, contents: header.data(using: .utf8))

        // Remove api notes file before we parse the swift interface
        if FileManager.default.fileExists(atPath: apinotesFile.string) {
            try FileManager.default.removeItem(atPath: apinotesFile.string)
        }

        // Exercize the AST code
        let ast = try await loadAST(headerPaths: headerPath, headerFile: headerFile)
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
            headerPaths: headerPath,
            moduleDir: modulemapFile.removingLastComponent(),
            moduleName: "SwiftSDL3",
            sdk: sdk,
            clangResourceDir: clangResourceDir,
            swiftResourceDir: swiftResourceDir,
            triple: triple
        )
        let syntaxText = String(describing: sourceFileSyntax)
        let syntaxFile = headerFile.removingLastComponent().appending("syntax.txt")
        FileManager.default.createFile(atPath: syntaxFile.string, contents: syntaxText.data(using: .utf8))

        var usedTypes: Set<String> = []

        // Functions that use OpaquePointer, replaced with wrappers

        let functions = sourceFileSyntax.statements.compactMap { item -> FunctionDeclSyntax? in
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
                    expression = LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: name))
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

            return function.with(\.signature, signature)
                .with(\.body, CodeBlockSyntax(
                    leadingTrivia: .space,
                    statements: .init([CodeBlockItemSyntax(item: .init(functionCall))]))
                )
        }

        let functionItems = functions.map { function in
            CodeBlockItemSyntax(item: .decl(.init(function)))
        }

        // The wrapper types for OpaquePointer

        let pointerType = OptionalTypeSyntax(
            wrappedType: IdentifierTypeSyntax(name: .identifier("OpaquePointer", leadingTrivia: .space))
        )

        let pointerVar = VariableDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public), trailingTrivia: .space)],
            bindingSpecifier: .keyword(.let, trailingTrivia: .space),
            bindings: [PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("pointer")),
                typeAnnotation: TypeAnnotationSyntax(type: pointerType)
            )]
        )

        let wrapperInit = InitializerDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public, trailingTrivia: .space))],
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: [FunctionParameterSyntax(
                        firstName: .wildcardToken(),
                        secondName: .identifier("pointer", leadingTrivia: .space),
                        type: pointerType
                    )]
                )
            ),
            body: CodeBlockSyntax(
                leadingTrivia: .space,
                statements: [CodeBlockItemSyntax(
                    leadingTrivia: [.newlines(1), .spaces(8)],
                    item: .init(InfixOperatorExprSyntax(
                        leftOperand: MemberAccessExprSyntax(
                            base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                            declName: DeclReferenceExprSyntax(baseName: .identifier("pointer"))),
                        operator: AssignmentExprSyntax(),
                        rightOperand: DeclReferenceExprSyntax(baseName: .identifier("pointer")),
                        trailingTrivia: [.newlines(1), .spaces(4)]
                    ),
                ))]
            )
        )

        let wrappers = usedTypes.sorted().map { type in 
            let wrapper = StructDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public), trailingTrivia: .space)],
                name: .identifier(type, leadingTrivia: .space, trailingTrivia: .space),
                memberBlock: MemberBlockSyntax(
                    members: [
                        MemberBlockItemSyntax(leadingTrivia: [.newlines(1), .spaces(4)], decl: pointerVar),
                        MemberBlockItemSyntax(leadingTrivia: [.newlines(1), .spaces(4)], decl: wrapperInit, trailingTrivia: .newline)
                    ],
                ),
                trailingTrivia: .newlines(2)
            )

            return CodeBlockItemSyntax(item: .init(wrapper))
        }

        let newSourceFile = SourceFileSyntax(statements: .init(wrappers + functionItems))
        FileManager.default.createFile(atPath: bindingsFile.string, contents: newSourceFile.description.data(using: .utf8))

        // TODO: Generate an API header to help with the Swift bindings
        let apiNotes = """
        Name: SwiftSDL3
        Functions:\n
        """ + functions.map { function in
            let name = function.name.text
            return """
            - Name: \(name)
              SwiftName: _\(name)(\(String(repeating: "_:", count: function.signature.parameterClause.parameters.count)))
            """
        }.joined(separator: "\n")
        FileManager.default.createFile(atPath: apinotesFile.string, contents: apiNotes.data(using: .utf8))
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

extension FilePath: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}
