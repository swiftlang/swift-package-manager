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

class AppState {
    // TODO: generate SDL_Window type
    var window: SDL_Window
    // TODO: generate SDL_Renderer type
    var renderer: SDL_Renderer

    var width: Int32 = 640
    var height: Int32 = 480
    var logWidth: Int32 = 640
    var logHeight: Int32 = 320

    var prevTime: UInt64

    init?() throws {
        let SDL_WINDOW_RESIZABLE: Uint64 = 0x0000000000000020

        self.window = SDL_CreateWindow("Hey", width, height, SDL_WINDOW_RESIZABLE)
        self.renderer = SDL_CreateRenderer(window, nil)

        _ = SDL_SetRenderLogicalPresentation(renderer, logWidth, logHeight, SDL_LOGICAL_PRESENTATION_LETTERBOX)

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
        _ = SDL_SetRenderDrawColor(renderer, 240, 81, 56, 255)
        _ = SDL_RenderClear(renderer)
    }

    deinit {
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
    }
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