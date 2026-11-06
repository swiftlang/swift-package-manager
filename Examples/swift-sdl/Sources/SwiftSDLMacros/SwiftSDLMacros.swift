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
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Attached to a class to make it a SwiftSDL app.
///
///     @SDLApp
///     final class MyApp { ... }
///
public struct SDLAppMacro {}

extension SDLAppMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@SDLApp can only be applied to a class")
        }

        // `protocols` only contains the conformances the class doesn't already have.
        guard !protocols.isEmpty else {
            return []
        }

        let inheritance = InheritanceClauseSyntax {
            for proto in protocols {
                InheritedTypeSyntax(type: proto)
            }
        }
        return [
            ExtensionDeclSyntax(
                extendedType: type,
                inheritanceClause: inheritance
            ) {}
        ]
    }
}

extension SDLAppMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@SDLApp can only be applied to a class")
        }

        let className = classDecl.name.trimmed

        return [
            // SDL_AppInit
            """
            @_cdecl("SDL_AppInit") public func SDL_AppInit(
                _ appState: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                _ argc: Int32,
                _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            ) -> SDL_AppResult {
                guard SDL_Init(SDL_INIT_VIDEO),
                      let appState,
                      let state = \(className)()
                else {
                    return SDL_APP_FAILURE
                }

                appState.pointee = Unmanaged.passRetained(state).toOpaque()

                return SDL_APP_CONTINUE
            }
            """,

            // SDL_AppEvent
            """
            @_cdecl("SDL_AppEvent") public func SDL_AppEvent(
                _ appState: UnsafeMutableRawPointer!,
                _ event: UnsafeMutablePointer<SDL_Event>!
            ) -> SDL_AppResult {
                let appState: \(className) = Unmanaged.fromOpaque(appState).takeUnretainedValue()

                return appState.handle(event: event.pointee)
            }
            """,

            // SDL_AppIterate
            """
            @_cdecl("SDL_AppIterate") public func SDL_AppIterate(
                _ appState: UnsafeMutableRawPointer!,
            ) -> SDL_AppResult {
                let appState: \(className) = Unmanaged.fromOpaque(appState).takeUnretainedValue()
            
                return appState.iterate()
            }
            """,

            // SDL_AppQuit
            """
            @_cdecl("SDL_AppQuit") public func SDL_AppQuit(
                _ appState: UnsafeMutableRawPointer!,
            ) {
                _ = Unmanaged<\(className)>.fromOpaque(appState).takeRetainedValue()
            }
            """
        ]
    }
}

@main
struct SwiftSDLMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SDLAppMacro.self,
    ]
}
