import Foundation

@main
struct SDLAPIGenerator {
    static func main() throws {
        let moduleMap = """
        module CSDL [system] {
            header "CSDL.h"
            export *
        }
        """

        let moduleMapFile = URL(fileURLWithPath: CommandLine.arguments[1])
        try moduleMap.write(to: moduleMapFile, atomically: true, encoding: .utf8)

        let header = """
        #define SDL_MAIN_USE_CALLBACKS 1
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_main.h>
        """

        let headerFile = URL(fileURLWithPath: CommandLine.arguments[2])
        try header.write(to: headerFile, atomically: true, encoding: .utf8)

        // TODO: Generate an API header to help with the Swift bindings
    } 
}
