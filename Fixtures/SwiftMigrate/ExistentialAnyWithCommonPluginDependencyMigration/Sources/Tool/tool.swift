import Foundation
import CommonLibrary

@main struct Entry {
    public static func main() async throws {
        common()
        let outputPath = CommandLine.arguments[1]
        let contents = """
        func generatedFunction() {}
        """
        FileManager.default.createFile(atPath: outputPath, contents: contents.data(using: .utf8))
    }
}
