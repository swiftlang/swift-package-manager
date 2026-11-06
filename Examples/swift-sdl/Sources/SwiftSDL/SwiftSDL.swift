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
import SDL3

public protocol SwiftSDLApp {
    static var initFlags: SDL_InitFlags { get }

    init?()

    func handle(event: SDL_Event) -> SDL_AppResult
    func iterate() -> SDL_AppResult
}

public extension SDL_Event {
    var eventType: SDL_EventType {
        #if os(Windows)
        SDL_EventType(Int32(self.type))
        #else
        SDL_EventType(self.type)
        #endif
    }
}

/// Conforms the attached class to `SwiftSDLApp` and generates the main callbacks
@attached(extension, conformances: SwiftSDLApp)
@attached(peer, names: named(SDL_AppInit), named(SDL_AppEvent), named(SDL_AppIterate), named(SDL_AppQuit))
public macro SDLApp() = #externalMacro(module: "SwiftSDLMacros", type: "SDLAppMacro")
