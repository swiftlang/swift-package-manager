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
import SwiftSDL3

@_cdecl("SDL_AppInit") public func SDL_AppInit(
    _ gameState: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> SDL_AppResult {
    guard SDL_Init(SDL_INIT_VIDEO),
          let gameState,
          let state = try? GameState()
    else {
        return SDL_APP_FAILURE
    }
    gameState.pointee = Unmanaged.passRetained(state).toOpaque()

    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppEvent") public func SDL_AppEvent(
    _ gameState: UnsafeMutableRawPointer!,
    _ event: UnsafeMutablePointer<SDL_Event>!
) -> SDL_AppResult {
    let gameState: GameState = Unmanaged.fromOpaque(gameState).takeUnretainedValue()

    return gameState.handle(event: event.pointee)
}

@_cdecl("SDL_AppIterate") public func SDL_AppIterate(
    _ gameState: UnsafeMutableRawPointer!,
) -> SDL_AppResult {
    let gameState: GameState = Unmanaged.fromOpaque(gameState).takeUnretainedValue()
    let nowTime = SDL_GetTicks()
    let deltaTime = (Float(nowTime) - Float(gameState.prevTime)) / 1000

    gameState.update(deltaTime: deltaTime)

    SDL_SetRenderDrawColor(gameState.renderer, 240, 81, 56, 255)
    SDL_RenderClear(gameState.renderer)

    gameState.draw()

    SDL_RenderPresent(gameState.renderer)

    gameState.prevTime = nowTime

    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppQuit") public func SDL_AppQuit(
    _ gameState: UnsafeMutableRawPointer!,
) {
    // Free the gamestate
    _ = Unmanaged<GameState>.fromOpaque(gameState).takeRetainedValue()
}
