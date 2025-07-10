import Foundation

@main struct Entry {
    public static func main() async throws {
        let outputPath = CommandLine.arguments[1]
        let contents = """
        func generatedFunction() {}
        func dontmodifyme(_: P) {}
        """
        FileManager.default.createFile(atPath: outputPath, contents: contents.data(using: .utf8))
    }
}
