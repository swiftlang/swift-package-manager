import Foundation
import Subprocess

@main
struct JarBuilder {
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

        let classFiles = try inputFiles.flatMap { try findClassFiles(in: $0) }

        guard !classFiles.isEmpty else {
            print("class files missing")
            exit(1)
        }

        let result = try await run(
            .name("jar"),
            arguments: .init([
                "-c",
                "-f", outputFile.path
            ] + classFiles.map({ $0.path })),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !result.terminationStatus.isSuccess {
            print("jar failed")
            exit(1)
        }

        print("Jar file complete")
    }

    static func findClassFiles(in directoryURL: URL) throws -> [URL] {
        var classFiles: [URL] = []

        let classDir = directoryURL.deletingLastPathComponent()
        if let enumerator = FileManager.default.enumerator(at: classDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "class" else { continue }
                classFiles.append(fileURL)
            }
        }

        return classFiles
    }
}