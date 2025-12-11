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

// This example is the basic structure of a template that uses string interpolation.
@main
struct HelloTemplateTool: ParsableCommand {
    @OptionGroup(visibility: .hidden)
    var packageOptions: PkgDir

    // swift argument parser needed to expose arguments to template generator
    @Option(help: "The name of your app")
    var name: String

    @Flag(help: "Include a README?")
    var includeReadme: Bool = false

    // entrypoint of the template executable, that generates just a main.swift and a readme.md
    func run() throws {
        guard let pkgDir = packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }

        let fs = FileManager.default

        let packageDir = FilePath(pkgDir)

        let mainFile = packageDir / "Sources" / self.name / "main.swift"

        try fs.createDirectory(atPath: mainFile.removingLastComponent().string, withIntermediateDirectories: true)

        try """
        // This is the entry point to your command-line app
        print("Hello, \(self.name)!")

        """.write(toFile: mainFile)

        if self.includeReadme {
            try """
            # \(self.name)
            This is a new Swift app!
            """.write(toFile: packageDir / "README.md")
        }

        print("Project generated at \(packageDir)")
    }
}

// MARK: - Shared option commands that are used to show inheritances of arguments and flags

struct PkgDir: ParsableArguments {
    @Option(help: .hidden)
    var pkgDir: String?
}
