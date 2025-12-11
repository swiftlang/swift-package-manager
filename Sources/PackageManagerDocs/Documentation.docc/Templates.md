#  Creating Package Templates

This guide provides a brief overview of Swift Package Manager templates, describes how a package can make use of templates, and shows how to get started writing your own templates.

## Overview

Custom _templates_ allow Swift Package Manager to generate of packages whose functionality goes beyond the hard-coded templates. Package templates are written in Swift using Swift Argument Parser to provide arguments for generating a Swift package.

A template is represented in the SwiftPM package manifest as a target of the `templateTarget` type and should be available to other packages by declaring a corresponding `template` product. Source code for a template is normally located in a directory under the `Templates` directory in the package, but this can be customized. However, as seen below, authors will also need to write the source code for a plugin.

Templates are an abstraction of two types of modules:
- a template _executable_ that performs the file generation and project setup
- a command-line _plugin_ that safely invokes the executable

The command-line plugin allows the template executable to run in a separate process, and (on platforms that support sandboxing) it is wrapped in a sandbox that prevents network access as well as attempts to write to arbitrary locations in the file system. Template plugins have access to the representation of the package model, which can be used by the template whenever the context of a package is needed; for example, to infer sensible defaults or validate user inputs against existing package structure.

The executable allows authors to define user-facing interfaces which gather important consumer input needed by the template to run, using Swift Argument Parser for a rich command-line experience with subcommands, options, and flags.

To learn about using a package template, read <doc:CreatingSwiftPackage#Creating-a-Package-based-on-a-custom-template>.

## Writing a Template

The first step when writing a package template is to decide what kind of template you need and what base package structure it should start with. Templates can build off of any kind of Swift package: executables, libraries, plugins, or even empty packages that will be further customized.

### Declaring a template in the package manifest

Like all package components, templates are declared in the package manifest. This is done using a `templateTarget` entry in the `targets` section of the package. Templates must be visible to other packages in order to be ran. Thus, there needs to be a corresponding `template` entry in the `products` section as well:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyTemplates",
    products: [
        .template(name: "LibraryTemplate"),
        .template(name: "ExecutableTemplate"),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .template(
            name: "LibraryTemplate",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            initialPackageType: .library,
            description: "Generate a Swift library package"
        ),
        .template(
            name: "ExecutableTemplate", 
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            initialPackageType: .executable,
            templatePermissions: [
                .writeToPackageDirectory(reason: "Generate source files and documentation"),
            ],
            description: "Generate an executable package with optional features"
        ),
    ]
)
```

The `templateTarget` declares the name and capability of the template, along with its dependencies. The `initialPackageType` specifies the base package structure that SwiftPM will set up before invoking the template — this can be `.library`, `.executable`, `.tool`, `.buildToolPlugin`, `.commandPlugin`, `.macro`, or `.empty`.

The Swift script files that implement the logic of the template are expected to be in a directory named the same as the template, located under the `Templates` subdirectory of the package. The template also expects Swift script files in a directory with the same name as the template, alongside a `Plugin` suffix, located under the `Plugins` subdirectory of the package.

The `template` product is what makes the template visible to other packages. The name of the template product must match the name of the target.

#### Template target dependencies

The dependencies specify the packages that will be available for use by the template executable. Each dependency can be any package product. Commonly this includes Swift Argument Parser for command-line interface handling, but can also include utilities for file generation, string processing, or network requests if needed.

#### Template permissions  

Templates specify what permissions they need through the `templatePermissions` parameter. Common permissions include:

```swift
templatePermissions: [
    .writeToPackageDirectory(reason: "Generate project files"),
    .allowNetworkConnections(scope: .none, reason: "Download additional resources"),
]
```

### Implementing the template command plugin script

The command plugin for a template acts as a bridge between SwiftPM and the template executable. By default, Swift Package Manager looks for plugin implementations in subdirectories of the `Plugins` directory named with the template name followed by "Plugin".

```swift
import Foundation
import PackagePlugin

@main
struct LibraryTemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "LibraryTemplate")
        let packageDirectory = context.package.directoryURL.path

        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = ["--package-directory", packageDirectory] + 
                           arguments.filter { $0 != "--" }
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()
        
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw TemplateError.executionFailed(
                code: process.terminationStatus, 
                stderrOutput: stderrOutput
            )
        }
    }
    
    enum TemplateError: Error, CustomStringConvertible {
        case executionFailed(code: Int32, stderrOutput: String)

        var description: String {
            switch self {
            case .executionFailed(let code, let stderrOutput):
                return """
                Template execution failed with exit code \(code).
                
                Error output:
                \(stderrOutput)
                """
            }
        }
    }
}
```

The plugin receives a `context` parameter that provides access to the consumer's package model and tool paths, similar to other SwiftPM plugins. The plugin is responsible for invoking the template executable with the appropriate arguments.

### Implementing the template executable

Template executables are Swift command-line programs that use Swift Argument Parser. The executable can define user-facing options, flags, arguments, subcommands, and hidden arguments that can be filled by the template plugin's `context`:

```swift
import ArgumentParser
import Foundation
import SystemPackage

@main
struct LibraryTemplate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library-template",
        abstract: "Generate a Swift library package with configurable features"
    )

    @OptionGroup(visibility: .hidden)
    var packageOptions: PackageOptions

    @Argument(help: "Name of the library")
    var name: String

    @Flag(help: "Include example usage in README")
    var examples: Bool = false

    func run() throws {
        guard let packageDirectory = packageOptions.packageDirectory else {
            throw TemplateError.missingPackageDirectory
        }

        print("Generating library '\(name)' at \(packageDirectory)")

        // Update Package.swift with the library name
        try updatePackageManifest(name: name, at: packageDirectory)

        // Create the main library file
        try createLibrarySource(name: name, at: packageDirectory)

        // Create tests
        try createTests(name: name, at: packageDirectory)

        if examples {
            try createReadmeWithExamples(name: name, at: packageDirectory)
        }

        print("Library template completed successfully!")
    }

    func updatePackageManifest(name: String, at directory: String) throws {
        let packagePath = "\(directory)/Package.swift"
        var content = try String(contentsOfFile: packagePath)
        
        // Update package name and target names
        content = content.replacingOccurrences(of: "name: \"Template\"", with: "name: \"\(name)\"")
        content = content.replacingOccurrences(of: "\"Template\"", with: "\"\(name)\"")
        
        try content.write(toFile: packagePath, atomically: true, encoding: .utf8)
    }

    func createLibrarySource(name: String, at directory: String) throws {
        let sourceContent = """
        /// \(name) provides functionality for [describe your library].
        public struct \(name) {
            /// Creates a new instance of \(name).
            public init() {}
            
            /// A sample method demonstrating the library's capabilities.
            public func hello() -> String {
                "Hello from \(name)!"
            }
        }
        """
        
        let sourcePath = "\(directory)/Sources/\(name)/\(name).swift"
        try FileManager.default.createDirectory(atPath: "\(directory)/Sources/\(name)", 
                                               withIntermediateDirectories: true)
        try sourceContent.write(toFile: sourcePath, atomically: true, encoding: .utf8)
    }

    func createTests(name: String, at directory: String) throws {
        let testContent = """
        import Testing
        @testable import \(name)

        struct \(name)Tests {
            @Test
            func testHello() {
                let library = \(name)()
                #expect(library.hello() == "Hello from \(name)!")
            }
        }
        """
        
        let testPath = "\(directory)/Tests/\(name)Tests/\(name)Tests.swift"
        try FileManager.default.createDirectory(atPath: "\(directory)/Tests/\(name)Tests",
                                               withIntermediateDirectories: true)
        try testContent.write(toFile: testPath, atomically: true, encoding: .utf8)
    }

    func createReadmeWithExamples(name: String, at directory: String) throws {
        let readmeContent = """
        # \(name)

        A Swift library that provides [describe functionality].

        ## Usage

        ```swift
        import \(name)

        let library = \(name)()
        print(library.hello()) // Prints: Hello from \(name)!
        ```

        ## Installation

        Add \(name) to your Package.swift dependencies:

        ```swift
        dependencies: [
            .package(url: "https://github.com/yourname/\(name.lowercased())", from: "1.0.0")
        ]
        ```
        """
        
        try readmeContent.write(toFile: "\(directory)/README.md", atomically: true, encoding: .utf8)
    }
}

struct PackageOptions: ParsableArguments {
    @Option(help: .hidden)
    var packageDirectory: String?
}

enum TemplateError: Error {
    case missingPackageDirectory
}
```

### Using package context for package defaults

Template plugins have access to the package context, which can be used by template authors to fill certain arguments to make package generation easier. Here's an example of how a template can use context information:

```swift
import PackagePlugin
import Foundation

@main  
struct SimpleTemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "SimpleTemplate")
        let packageDirectory = context.package.directoryURL.path
        
        // Extract information from the package context
        let packageName = context.package.displayName
        let existingTargets = context.package.targets.map { $0.name }
        
        // Pass context information to the template executable
        var templateArgs = [
            "--package-directory", packageDirectory,
            "--package-name", packageName,
            "--existing-targets", existingTargets.joined(separator: ",")
        ]
        
        templateArgs.append(contentsOf: arguments.filter { $0 != "--" })

        let process = Process()
        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = templateArgs

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw TemplateError.executionFailed(code: process.terminationStatus)
        }
    }
}
```

The corresponding template executable can then use this context to provide the template with essential information regarding the consumer's package:

```swift
@main
struct IntelligentTemplate: ParsableCommand {
    @OptionGroup(visibility: .hidden)
    var packageOptions: PackageOptions
    
    @Option(help: .hidden)
    var packageName: String?
    
    @Option(help: .hidden)
    var existingTargets: String?
    
    @Option(help: "Name for the new component")
    var componentName: String?

    func run() throws {
        // Use package context to provide intelligent defaults
        let inferredName = componentName ?? packageName?.appending("Utils") ?? "Component"
        let existingTargetList = existingTargets?.split(separator: ",").map(String.init) ?? []
        
        // Validate that we're not creating duplicate targets
        if existingTargetList.contains(inferredName) {
            throw TemplateError.targetAlreadyExists(inferredName)
        }
        
        print("Creating component '\(inferredName)' (inferred from package context)")
        // ... rest of template implementation
    }
}
```

### Templates with subcommands

Templates can use subcommands to create branching decision trees, allowing users to choose between different variants:

```swift
@main
struct MultiVariantTemplate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "multivariant-template",
        abstract: "Generate different types of Swift projects",
        subcommands: [WebApp.self, CLI.self, Library.self]
    )

    @OptionGroup(visibility: .hidden)
    var packageOptions: PackageOptions

    @Flag(help: "Include comprehensive documentation")
    var documentation: Bool = false
    
    func run() throws {
        ...
    }
}

struct WebApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webapp",
        abstract: "Generate a web application"
    )

    @ParentCommand var template: MultiVariantTemplate

    @Option(help: "Web framework to use")
    var framework: WebFramework = .vapor

    @Flag(help: "Include authentication support")
    var auth: Bool = false

    func run() throws {
        print("Generating web app with \(framework.rawValue) framework")
        
        if template.documentation {
            print("Including comprehensive documentation")
        }
        
        // Generate web app specific files...
    }
}

struct CLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cli",
        abstract: "Generate a command-line tool"
    )

    @ParentCommand var template: MultiVariantTemplate

    @Flag(help: "Include shell completion support")
    var completion: Bool = false

    func run() throws {
        template.run()
        print("Generating CLI tool")
        // Generate CLI specific files...
    }
}

enum WebFramework: String, ExpressibleByArgument, CaseIterable {
    case vapor, hummingbird
}
```

Subcommands can access shared logic and state from their parent command using the `@ParentCommand` property wrapper. This enables a clean seperation of logic between the different layers of commands, while still allowing sequential execution and reuse of common configuration or setup code define at the higher levels.

## Testing Templates

SwiftPM provides a built-in command for testing templates comprehensively:

```shell
❯ swift test template --template-name MyTemplate --output-path ./test-output
```

This command will:
1. Build the template executable
2. Prompt for all required inputs
3. Generate each possible decision path through subcommands
4. Validate that each variant builds successfully
5. Report results in a summary format

For templates with many variants, you can provide predetermined arguments to test specific paths:

```shell
❯ swift test template --template-name MultiVariantTemplate --output-path ./test-output webapp --framework vapor --auth
```

Templates can also include unit tests for their logic by factoring out file generation and validation code into testable functions.

