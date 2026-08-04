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

        let classFiles = try inputFiles.flatMap { try findClassFiles(in: $0.deletingLastPathComponent()) }

        guard !classFiles.isEmpty else {
            print("class files missing")
            exit(1)
        }

        let result = try await run(
            .name("jar"),
            arguments: .init([
                "-c",
                "-f", outputFile.path,
                // TODO: this should be a build setting so we don't need to hard code it
                "-e", "HelloWorld",
            ] + classFiles),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !result.terminationStatus.isSuccess {
            print("jar failed")
            exit(1)
        }

        print("Jar file complete")
    }

    static func findClassFiles(in directoryURL: URL) throws -> [String] {
        let baseComponents = directoryURL.standardizedFileURL.pathComponents
        var classFiles: [String] = ["-C", directoryURL.path]

        let classDir = directoryURL.deletingLastPathComponent()
        if let enumerator = FileManager.default.enumerator(at: classDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "class" else { continue }

                // return the relative path to the dir                
                let components = fileURL.standardizedFileURL.pathComponents
                guard components.starts(with: baseComponents) else { continue }

                classFiles.append(components.dropFirst(baseComponents.count).joined(separator: "/"))
            }
        }

        return classFiles
    }
}