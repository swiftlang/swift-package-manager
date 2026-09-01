import Foundation

@main
struct SwiftSDLGenerator {
    static func main() throws {
        let moduleMap = """
        module SDL [system] {
            header "SDL.h"
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
        let apiNotes = """
        Name: SDL
        Functions:
        - Name: SDL_GetVersion
          SwiftName: SwiftSDL_GetVersion()
        """

        let apiNotesFile = moduleMapFile.deletingLastPathComponent().appending(path: "SDL.apinotes")
        try apiNotes.write(to: apiNotesFile, atomically: true, encoding: .utf8)

        // TODO: Generate Swift bindings to make the Swift interface more ergonomic.
        // This includes replacing occurences of OpaquePointer with a more type safe alternative
        // by parsing the interfaces that use opaque structs and create replacements.
        let bindings = """
        """

        let bindingsFile = URL(fileURLWithPath: CommandLine.arguments[3])
        try bindings.write(to: bindingsFile, atomically: true, encoding: .utf8)
    }
}
