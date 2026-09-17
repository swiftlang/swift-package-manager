import SwiftSDL3

class GameState {
    var window: UnsafeMutablePointer<SDL_Window>
    var renderer: UnsafeMutablePointer<SDL_Renderer>

    var width: Int32 = 640
    var height: Int32 = 480
    var logWidth: Int32 = 640
    var logHeight: Int32 = 320

    var prevTime: UInt64

    init?() throws {
        let SDL_WINDOW_RESIZABLE: Uint64 = 0x0000000000000020

        guard let window = SDL_CreateWindow("Hey", width, height, SDL_WINDOW_RESIZABLE) else {
            return nil
        }
        self.window = window

        guard let renderer = SDL_CreateRenderer(window, nil) else {
            return nil
        }
        SDL_SetRenderLogicalPresentation(renderer, logWidth, logHeight, SDL_LOGICAL_PRESENTATION_LETTERBOX)
        self.renderer = renderer

        self.prevTime = SDL_GetTicks()
    }

    func handle(event: SDL_Event) -> SDL_AppResult {
        switch event.eventType {
        case SDL_EVENT_KEY_UP:
            if event.key.scancode == SDL_SCANCODE_ESCAPE {
                return SDL_APP_SUCCESS
            } else if event.key.scancode == SDL_SCANCODE_Q {
                return SDL_APP_SUCCESS
            }
        case SDL_EVENT_WINDOW_RESIZED:
            width = event.window.data1
            height = event.window.data2
        case SDL_EVENT_QUIT:
            return SDL_APP_SUCCESS
        default:
            break
        }

        return SDL_APP_CONTINUE
    }

    func update(deltaTime: Float) {
    }

    func draw() {
    }

    deinit {
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
    }
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

extension SDL_Event {
    var eventType: SDL_EventType {
        #if os(Windows)
        SDL_EventType(Int32(self.type))
        #else
        SDL_EventType(self.type)
        #endif
    }
}