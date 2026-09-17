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