import SwiftSDL3

func foo() {
    // SDL_GetVersion renamed in API notes
    print(SwiftSDL_GetVersion(), "Tests")
    sayVersion()
}
