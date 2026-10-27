import SwiftSDL
import SDL3

@SDLApp
final class MyApp {
    static let initFlags = SDL_INIT_VIDEO

    var window: OpaquePointer
    var renderer: OpaquePointer

    var width: Int32 = 640
    var height: Int32 = 480
    var logWidth: Int32 = 640
    var logHeight: Int32 = 320

    var prevTime: UInt64

    init?() {
        let SDL_WINDOW_RESIZABLE: Uint64 = 0x0000000000000020

        self.window = SDL_CreateWindow("Hey", width, height, SDL_WINDOW_RESIZABLE)
        self.renderer = SDL_CreateRenderer(window, nil)

        _ = SDL_SetRenderLogicalPresentation(renderer, logWidth, logHeight, SDL_LOGICAL_PRESENTATION_LETTERBOX)

        self.prevTime = SDL_GetTicks()
    }

    deinit {
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
    }

    func handle(event: SDL_Event) -> SDL_AppResult {
        switch event.eventType {
        case SDL_EVENT_WINDOW_RESIZED:
            width = event.window.data1
            height = event.window.data2
        case SDL_EVENT_KEY_UP:
            if event.key.scancode == SDL_SCANCODE_ESCAPE {
                return SDL_APP_SUCCESS
            } else if event.key.scancode == SDL_SCANCODE_Q {
                return SDL_APP_SUCCESS
            }
        case SDL_EVENT_QUIT:
            return SDL_APP_SUCCESS
        default:
            break
        }

        return SDL_APP_CONTINUE
    }

    func iterate() -> SDL_AppResult {
        _ = SDL_SetRenderDrawColor(renderer, 240, 81, 56, 255)
        _ = SDL_RenderClear(renderer)
        _ = SDL_RenderPresent(renderer)

        return SDL_APP_CONTINUE
    }
}
