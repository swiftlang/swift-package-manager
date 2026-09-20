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

@main
struct SwiftSDLGenerator {
    static func main() async throws {
        let moduleMap = """
        module SwiftSDL3 [system] {
            header "SDL.h"
            export *
        }
        """

        let moduleMapFile = URL(fileURLWithPath: CommandLine.arguments[1])
        try moduleMap.write(to: moduleMapFile, atomically: true, encoding: .utf8)

        let header = """
        #define SDL_MAIN_USE_CALLBACKS 1
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_main.h>

        // Dummies for OpaquePointer, don't use these
        //struct SDL_Window { int _private; };
        //struct SDL_Renderer { int _private; };
        //struct SDL_IOStream { int _private; };
        """

        let headerFile = URL(fileURLWithPath: CommandLine.arguments[2])
        try header.write(to: headerFile, atomically: true, encoding: .utf8)

        // TODO: Generate an API header to help with the Swift bindings
        let apiNotes = """
        Name: SwiftSDL3
        Functions:
        - Name: SDL_GetVersion
          SwiftName: SwiftSDL_GetVersion()
        """

        let apiNotesFile = moduleMapFile.deletingLastPathComponent().appending(path: "SwiftSDL3.apinotes")
        try apiNotes.write(to: apiNotesFile, atomically: true, encoding: .utf8)

        // TODO: Generate Swift bindings to make the Swift interface more ergonomic.
        // This includes replacing occurences of OpaquePointer with a more type safe alternative
        // by parsing the interfaces that use opaque structs and create replacements.
        let bindings = """
        """

        let bindingsFile = URL(fileURLWithPath: CommandLine.arguments[3])
        try bindings.write(to: bindingsFile, atomically: true, encoding: .utf8)

        // Exercize the AST code
        let headerPaths = [URL(fileURLWithPath: CommandLine.arguments[4])]
        let ast = try await loadAST(headerPaths: headerPaths, headerFile: headerFile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let astData = try encoder.encode(ast)
        let astURL = headerFile.deletingLastPathComponent().appending(path: "ast.json")
        try astData.write(to: astURL)

        // Exercise the parsing of the swiftinterface
        let sourceFileSyntax = try await parseInterface(
            headerPaths: headerPaths,
            moduleDir: moduleMapFile.deletingLastPathComponent(),
            moduleName: "SwiftSDL3"
        )
        let syntaxText = String(describing: sourceFileSyntax)
        let syntaxURL = headerFile.deletingLastPathComponent().appending(path: "syntax.txt")
        try syntaxText.data(using: .utf8)?.write(to: syntaxURL)

        let opaques = sourceFileSyntax.statements.compactMap { item in
            guard let function = item.item.as(FunctionDeclSyntax.self),
                let returnType = function.signature.returnClause?.type,
                let iuo = returnType.as(ImplicitlyUnwrappedOptionalTypeSyntax.self),
                iuo.wrappedType.as(IdentifierTypeSyntax.self)?.name.text == "OpaquePointer"
            else {
                return nil
            }

            return function.name.text
        }.joined(separator: "\n") + "\n"
        let opaquesURL = headerFile.deletingLastPathComponent().appending(path: "opaques.txt")
        try opaques.data(using: .utf8)?.write(to: opaquesURL)
    }
}
