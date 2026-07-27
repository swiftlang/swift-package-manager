import Foundation

@main
struct SwiftSDLGenerator {
    static func main() throws {
        let bindings = """
        @_exported import CSDL3
        """

        let bindingsFile = URL(fileURLWithPath: CommandLine.arguments[1])
        try bindings.write(to: bindingsFile, atomically: true, encoding: .utf8)
    }
}
