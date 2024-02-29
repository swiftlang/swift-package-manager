import Foundation

@main
struct Tool {
    static func main() async throws {
        let path = CommandLine.arguments[2]
        print("Printing file at \(path)")
        print(try String(contentsOfFile: path))
    }
}
