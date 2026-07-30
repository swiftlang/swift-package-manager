import Foundation

@main
struct SwiftSDLGenerator {
    static func main() throws {
        let bindings = """
        @_exported import CSDL
        """

        let bindingsFile = URL(fileURLWithPath: CommandLine.arguments[1])
        try bindings.write(to: bindingsFile, atomically: true, encoding: .utf8)

        // TODO: Generate Swift bindings to make the Swift interface more ergonomic.
        // This includes replacing occurences of OpaquePointer with a more type safe alternative
        // by parsing the interfaces that use opaque structs and create replacements.
    }
}
