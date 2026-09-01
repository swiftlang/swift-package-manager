import Testing
import SDL

@Test func example() async throws {
    // SDL_GetVersion renamed in API notes
    print(SwiftSDL_GetVersion(), "Tests")
    sayVersion()
}
