import Foundation
import Subprocess

@main
struct JavaBuilder {
    static func main() async throws {
        var inputFiles: [URL] = []
        var outputFile: URL? = nil
        var i = 1
        while i < CommandLine.arguments.count {
            switch CommandLine.arguments[i] {
                case "-o":
                    i += 1
                    outputFile = URL(fileURLWithPath: CommandLine.arguments[i])
                default:
                    inputFiles.append(URL(fileURLWithPath: CommandLine.arguments[i]))
            }
            i += 1
        }

        guard let outputFile else {
            print("output file missing")
            exit(1)
        }

        let outputDir = outputFile.deletingLastPathComponent()

        let result = try await run(
            .name("javac"),
            arguments: .init([
                "-d", outputDir.path
            ] + inputFiles.map({ $0.path })),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !result.terminationStatus.isSuccess {
            print("javac failed")
            exit(1)
        }

        try "".write(to: outputFile, atomically: true, encoding: .utf8)
        print("Java compile complete")
    }
}