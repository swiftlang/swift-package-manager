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
import Testing
import SwiftSDL3

@Test func example() async throws {
    print(SDL_GetVersion(), "Tests")
    sayVersion()
}

@_cdecl("SDL_AppInit") public func SDL_AppInit(
    _ appState: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> SDL_AppResult {
    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppEvent") public func SDL_AppEvent(
    _ appState: UnsafeMutableRawPointer!,
    _ event: UnsafeMutablePointer<SDL_Event>!
) -> SDL_AppResult {
    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppIterate") public func SDL_AppIterate(
    _ appState: UnsafeMutableRawPointer!,
) -> SDL_AppResult {
    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppQuit") public func SDL_AppQuit(
    _ appState: UnsafeMutableRawPointer!,
) {
}