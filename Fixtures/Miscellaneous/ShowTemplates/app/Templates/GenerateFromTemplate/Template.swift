import ArgumentParser
import Foundation
import SystemPackage

extension FilePath {
    static func / (left: FilePath, right: String) -> FilePath {
        left.appending(right)
    }
}

extension String {
    func write(toFile: FilePath) throws {
        try self.write(toFile: toFile.string, atomically: true, encoding: .utf8)
    }
}

// basic structure of a template that uses string interpolation
@main
struct HelloTemplateTool: ParsableCommand {
    // swift argument parser needed to expose arguments to template generator
    @Option(help: "The name of your app")
    var name: String

    @Flag(help: "Include a README?")
    var includeReadme: Bool = false

    // entrypoint of the template executable, that generates just a main.swift and a readme.md
    func run() throws {
        print("we got here")
        let fs = FileManager.default

        let rootDir = FilePath(fs.currentDirectoryPath)

        let mainFile = rootDir / "Generated" / self.name / "main.swift"

        try fs.createDirectory(atPath: mainFile.removingLastComponent().string, withIntermediateDirectories: true)

        try """
        // This is the entry point to your command-line app
        print("Hello, \(self.name)!")

        """.write(toFile: mainFile)

        if self.includeReadme {
            try """
            # \(self.name)
            This is a new Swift app!
            """.write(toFile: rootDir / "README.md")
        }

        print("Project generated at \(rootDir)")
    }
}
