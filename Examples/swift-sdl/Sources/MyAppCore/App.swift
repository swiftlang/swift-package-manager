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
    _ appState: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> SDL_AppResult {
    guard SDL_Init(SDL_INIT_VIDEO),
          let appState,
          let state = try? AppState()
    else {
        return SDL_APP_FAILURE
    }
    appState.pointee = Unmanaged.passRetained(state).toOpaque()

    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppEvent") public func SDL_AppEvent(
    _ appState: UnsafeMutableRawPointer!,
    _ event: UnsafeMutablePointer<SDL_Event>!
) -> SDL_AppResult {
    let appState: AppState = Unmanaged.fromOpaque(appState).takeUnretainedValue()

    return appState.handle(event: event.pointee)
}

@_cdecl("SDL_AppIterate") public func SDL_AppIterate(
    _ appState: UnsafeMutableRawPointer!,
) -> SDL_AppResult {
    let appState: AppState = Unmanaged.fromOpaque(appState).takeUnretainedValue()
    let nowTime = SDL_GetTicks()
    let deltaTime = (Float(nowTime) - Float(appState.prevTime)) / 1000

    appState.update(deltaTime: deltaTime)

    appState.draw()

    _ = SDL_RenderPresent(appState.renderer)

    appState.prevTime = nowTime

    return SDL_APP_CONTINUE
}

@_cdecl("SDL_AppQuit") public func SDL_AppQuit(
    _ appState: UnsafeMutableRawPointer!,
) {
    // Free the appState
    _ = Unmanaged<AppState>.fromOpaque(appState).takeRetainedValue()
}
