//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCBasic
import PackageModel

/// Create an initial template package.
public final class InitPackage {
    /// The tool version to be used for new packages.
    public static let newPackageToolsVersion = ToolsVersion.current

    /// Options for the template package.
    public struct InitPackageOptions {
        /// The type of package to create.
        public var packageType: PackageType

        /// The list of platforms in the manifest.
        ///
        /// Note: This should only contain Apple platforms right now.
        public var platforms: [SupportedPlatform]

        public init(
            packageType: PackageType,
            platforms: [SupportedPlatform] = []
        ) {
            self.packageType = packageType
            self.platforms = platforms
        }
    }

    /// Represents a package type for the purposes of initialization.
    public enum PackageType: String, CustomStringConvertible {
        case empty = "empty"
        case library = "library"
        case executable = "executable"
        case tool = "tool"
        case buildToolPlugin = "build-tool-plugin"
        case commandPlugin = "command-plugin"
        case macro = "macro"

        public var description: String {
            return rawValue
        }
    }

    /// A block that will be called to report progress during package creation
    public var progressReporter: ((String) -> Void)?

    /// The file system to use
    let fileSystem: FileSystem

    /// Where to create the new package
    let destinationPath: AbsolutePath

    /// The type of package to create.
    var packageType: PackageType { options.packageType }

    /// The options for package to create.
    let options: InitPackageOptions

    /// The name of the package to create.
    let pkgname: String

    /// The name of the target to create.
    var moduleName: String

    /// The name of the type to create (within the package).
    var typeName: String {
        return moduleName
    }

    /// Create an instance that can create a package with given arguments.
    public convenience init(
        name: String,
        packageType: PackageType,
        destinationPath: AbsolutePath,
        fileSystem: FileSystem
    ) throws {
        try self.init(
            name: name,
            options: InitPackageOptions(packageType: packageType),
            destinationPath: destinationPath,
            fileSystem: fileSystem
        )
    }

    /// Create an instance that can create a package with given arguments.
    public init(
        name: String,
        options: InitPackageOptions,
        destinationPath: AbsolutePath,
        fileSystem: FileSystem
    ) throws {
        self.options = options
        self.pkgname = name
        self.moduleName = name.spm_mangledToC99ExtendedIdentifier()
        self.destinationPath = destinationPath
        self.fileSystem = fileSystem
    }

    /// Actually creates the new package at the destinationPath
    public func writePackageStructure() throws {
        progressReporter?("Creating \(packageType) package: \(pkgname)")

        // FIXME: We should form everything we want to write, then validate that
        // none of it exists, and then act.
        try writeManifestFile()
        try writeGitIgnore()
        try writePlugins()
        try writeSources()
        try writeTests()
    }

    private func writePackageFile(_ path: AbsolutePath, body: (OutputByteStream) -> Void) throws {
        progressReporter?("Creating \(path.relative(to: destinationPath))")
        try self.fileSystem.writeFileContents(path, body: body)
    }

    private func writeManifestFile() throws {
        let manifest = destinationPath.appending(component: Manifest.filename)
        guard self.fileSystem.exists(manifest) == false else {
            throw InitError.manifestAlreadyExists
        }

        try writePackageFile(manifest) { stream in
            stream <<< """
                // The swift-tools-version declares the minimum version of Swift required to build this package.

                import PackageDescription

                """

            if packageType == .macro {
                stream <<< """
                  import CompilerPluginSupport

                  """
            }

            stream <<< """

                let package = Package(

                """

            var pkgParams = [String]()
            pkgParams.append("""
                    name: "\(pkgname)"
                """)

            var platforms = options.platforms

            // Macros require macOS 10.15, iOS 13, etc.
            if packageType == .macro {
                func addIfMissing(_ newPlatform: SupportedPlatform) {
                  if platforms.contains(where: { platform in
                      platform.platform == newPlatform.platform
                  }) {
                      return
                  }

                  platforms.append(newPlatform)
                }

              addIfMissing(.init(platform: .macOS, version: .init("10.15")))
              addIfMissing(.init(platform: .iOS, version: .init("13")))
              addIfMissing(.init(platform: .tvOS, version: .init("13")))
              addIfMissing(.init(platform: .watchOS, version: .init("6")))
              addIfMissing(.init(platform: .macCatalyst, version: .init("13")))
            }

            var platformsParams = [String]()
            for supportedPlatform in platforms {
                let version = supportedPlatform.version
                let platform = supportedPlatform.platform

                var param = ".\(platform.manifestName)("
                if supportedPlatform.isManifestAPIAvailable {
                    if version.minor > 0 {
                        param += ".v\(version.major)_\(version.minor)"
                    } else {
                        param += ".v\(version.major)"
                    }
                } else {
                    param += "\"\(version.versionString)\""
                }
                param += ")"

                platformsParams.append(param)
            }

            // Package platforms
            if !platforms.isEmpty {
                pkgParams.append("""
                        platforms: [\(platformsParams.joined(separator: ", "))]
                    """)
            }

            // Package products
            if packageType == .library {
                pkgParams.append("""
                    products: [
                        // Products define the executables and libraries a package produces, making them visible to other packages.
                        .library(
                            name: "\(pkgname)",
                            targets: ["\(pkgname)"]),
                    ]
                """)
            } else if packageType == .buildToolPlugin || packageType == .commandPlugin {
                pkgParams.append("""
                    products: [
                        // Products can be used to vend plugins, making them visible to other packages.
                        .plugin(
                            name: "\(pkgname)",
                            targets: ["\(pkgname)"]),
                    ]
                """)
            } else if packageType == .macro {
                pkgParams.append("""
                    products: [
                        // Products define the executables and libraries a package produces, making them visible to other packages.
                        .library(
                            name: "\(pkgname)",
                            targets: ["\(pkgname)"]),
                        .executable(
                            name: "\(pkgname)Client",
                            targets: ["\(pkgname)Client"]
                        ),
                    ]
                """)

            }

            // Package dependencies
            if packageType == .tool {
                pkgParams.append("""
                    dependencies: [
                        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
                    ]
                """)
            } else if packageType == .macro {
                pkgParams.append("""
                    dependencies: [
                        // Depend on the latest Swift 5.9 prerelease of SwiftSyntax
                        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0-swift-5.9-DEVELOPMENT-SNAPSHOT-2023-04-10-a"),
                    ]
                """)
            }

            // Package targets
            if packageType != .empty {
                var param = ""

                param += """
                    targets: [
                        // Targets are the basic building blocks of a package, defining a module or a test suite.
                        // Targets can depend on other targets in this package and products from dependencies.

                """
                if packageType == .executable {
                    param += """
                            .executableTarget(
                                name: "\(pkgname)")
                        ]
                    """
                } else if packageType == .tool {
                    param += """
                            .executableTarget(
                                name: "\(pkgname)",
                                dependencies: [
                                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                                ]),
                        ]
                    """
                } else if packageType == .buildToolPlugin {
                    param += """
                            .plugin(
                                name: "\(typeName)",
                                capability: .buildTool()
                            ),
                        ]
                    """
                } else if packageType == .commandPlugin {
                    param += """
                            .plugin(
                                name: "\(typeName)",
                                capability: .command(intent: .custom(
                                    verb: "\(typeName)",
                                    description: "prints hello world"
                                ))
                            ),
                        ]
                    """
                } else if packageType == .macro {
                    param += """
                            // Macro implementation, only built for the host and never part of a client program.
                            .macro(name: "\(pkgname)Macros",
                                   dependencies: [
                                     .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                     .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                                   ]
                            ),

                            // Library that exposes a macro as part of its API, which is used in client programs.
                            .target(name: "\(pkgname)", dependencies: ["\(pkgname)Macros"]),

                            // A client of the library, which is able to use the macro in its
                            // own code.
                            .executableTarget(name: "\(pkgname)Client", dependencies: ["\(pkgname)"]),

                            // A test target used to develop the macro implementation.
                            .testTarget(
                                name: "\(pkgname)Tests",
                                dependencies: [
                                   "\(pkgname)Macros",
                                ]
                            ),
                        ]
                    """
                } else {
                    param += """
                            .target(
                                name: "\(pkgname)"),
                            .testTarget(
                                name: "\(pkgname)Tests",
                                dependencies: ["\(pkgname)"]),
                        ]
                    """
                }

                pkgParams.append(param)
            }

            stream <<< pkgParams.joined(separator: ",\n") <<< "\n)\n"
        }

        // Create a tools version with current version but with patch set to zero.
        // We do this to avoid adding unnecessary constraints to patch versions, if
        // the package really needs it, they should add it manually.
        let version = packageType == .macro ? ToolsVersion.vNext
            : InitPackage.newPackageToolsVersion.zeroedPatch

        // Write the current tools version.
        try ToolsVersionSpecificationWriter.rewriteSpecification(
            manifestDirectory: manifest.parentDirectory,
            toolsVersion: version,
            fileSystem: self.fileSystem
        )
    }

    private func writeGitIgnore() throws {
        guard packageType != .empty else {
            return
        }
        let gitignore = destinationPath.appending(".gitignore")
        guard self.fileSystem.exists(gitignore) == false else {
            return
        }

        try writePackageFile(gitignore) { stream in
            stream <<< """
                .DS_Store
                /.build
                /Packages
                xcuserdata/
                DerivedData/
                .swiftpm/configuration/registries.json
                .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
                .netrc

                """
        }
    }

    private func writePlugins() throws {
        switch packageType {
        case .buildToolPlugin, .commandPlugin:
            let plugins = destinationPath.appending(component: "Plugins")
            guard self.fileSystem.exists(plugins) == false else {
                return
            }
            progressReporter?("Creating \(plugins.relative(to: destinationPath))/")
            try makeDirectories(plugins)

            let moduleDir = plugins
            try makeDirectories(moduleDir)

            let sourceFileName = "\(pkgname).swift"
            let sourceFile = try AbsolutePath(validating: sourceFileName, relativeTo: moduleDir)

            var content = """
                import PackagePlugin

                @main

                """
            if packageType == .buildToolPlugin {
                content += """
                struct \(typeName): BuildToolPlugin {
                    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
                        // The plugin can choose what parts of the package to process.
                        guard let sourceFiles = target.sourceModule?.sourceFiles else { return [] }

                        // Find the code generator tool to run (replace this with the actual one).
                        let generatorTool = try context.tool(named: "my-code-generator")

                        // Construct a build command for each source file with a particular suffix.
                        return sourceFiles.map(\\.path).compactMap { inputPath in
                            guard inputPath.extension == "my-input-suffix" else { return .none }
                            let inputName = inputPath.lastComponent
                            let outputName = inputPath.stem + ".swift"
                            let outputPath = context.pluginWorkDirectory.appending(outputName)
                            return .buildCommand(
                                displayName: "Generating \\(outputName) from \\(inputName)",
                                executable: generatorTool.path,
                                arguments: ["\\(inputPath)", "-o", "\\(outputPath)"],
                                inputFiles: [inputPath],
                                outputFiles: [outputPath]
                            )
                        }
                    }
                }

                """
            }
            else {
                content += """
                struct \(typeName): CommandPlugin {
                    func performCommand(context: PluginContext, arguments: [String]) async throws {
                        print("Hello, World!")
                    }
                }

                """
            }

            try writePackageFile(sourceFile) { stream in
                stream.write(content)
            }

        case .empty, .library, .executable, .tool, .macro:
            break
        }
    }

    private func writeSources() throws {
        if packageType == .empty || packageType == .buildToolPlugin || packageType == .commandPlugin {
            return
        }

        let sources = destinationPath.appending("Sources")
        guard self.fileSystem.exists(sources) == false else {
            return
        }
        progressReporter?("Creating \(sources.relative(to: destinationPath))/")
        try makeDirectories(sources)

        let moduleDir: AbsolutePath
        switch packageType {
        case .executable, .tool:
            moduleDir = sources
        default:
            moduleDir = sources.appending("\(pkgname)")
        }
        try makeDirectories(moduleDir)

        let sourceFileName: String
        if packageType == .executable {
            sourceFileName = "main.swift"
        } else {
            sourceFileName = "\(typeName).swift"
        }
        let sourceFile = try AbsolutePath(validating: sourceFileName, relativeTo: moduleDir)

        let content: String
        switch packageType {
        case .library:
            content = """
                // The Swift Programming Language
                // https://docs.swift.org/swift-book

                """
        case .executable:
            content = """
                // The Swift Programming Language
                // https://docs.swift.org/swift-book

                print("Hello, world!")

                """
        case .tool:
            content = """
            // The Swift Programming Language
            // https://docs.swift.org/swift-book
            // 
            // Swift Argument Parser
            // https://swiftpackageindex.com/apple/swift-argument-parser/documentation

            import ArgumentParser

            @main
            struct \(typeName): ParsableCommand {
                mutating func run() throws {
                    print("Hello, world!")
                }
            }
            """
        case .macro:
            content = """
            // The Swift Programming Language
            // https://docs.swift.org/swift-book

            /// A macro that produces both a value and a string containing the
            /// source code that generated the value. For example,
            ///
            ///     #stringify(x + y)
            ///
            /// produces a tuple `(x + y, "x + y")`.
            @freestanding(expression)
            public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "\(moduleName)Macros", type: "StringifyMacro")
            """

        case .empty, .buildToolPlugin, .commandPlugin:
            throw InternalError("invalid packageType \(packageType)")
        }

        try writePackageFile(sourceFile) { stream in
            stream.write(content)
        }

        if packageType == .macro {
          try writeMacroPluginSources(sources.appending("\(pkgname)Macros"))
          try writeMacroClientSources(sources.appending("\(pkgname)Client"))
        }
    }

    private func writeTests() throws {
        switch packageType {
        case .empty, .executable, .tool, .buildToolPlugin, .commandPlugin: return
            default: break
        }
        let tests = destinationPath.appending("Tests")
        guard self.fileSystem.exists(tests) == false else {
            return
        }
        progressReporter?("Creating \(tests.relative(to: destinationPath))/")
        try makeDirectories(tests)
        try writeTestFileStubs(testsPath: tests)
    }

    private func writeLibraryTestsFile(_ path: AbsolutePath) throws {
        try writePackageFile(path) { stream in
            stream <<< """
                import XCTest
                @testable import \(moduleName)

                final class \(moduleName)Tests: XCTestCase {
                    func testExample() throws {
                        // XCTest Documentation
                        // https://developer.apple.com/documentation/xctest

                        // Defining Test Cases and Test Methods
                        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
                    }
                }

                """
        }
    }

    private func writeMacroTestsFile(_ path: AbsolutePath) throws {
        try writePackageFile(path) { stream in
            stream <<< ##"""
                import SwiftSyntax
                import SwiftSyntaxBuilder
                import SwiftSyntaxMacros
                import XCTest
                import \##(moduleName)Macros

                var testMacros: [String: Macro.Type] = [
                    "stringify" : StringifyMacro.self,
                ]

                final class \##(moduleName)Tests: XCTestCase {
                    func testMacro() {
                        // XCTest Documentation
                        // https://developer.apple.com/documentation/xctest

                        // Test input is a source file containing uses of the macro.
                        let sf: SourceFileSyntax =
                            #"""
                            let a = #stringify(x + y)
                            let b = #stringify("Hello, \(name)")
                            """#

                        let context = BasicMacroExpansionContext(
                            sourceFiles: [sf: .init(moduleName: "MyModule", fullFilePath: "test.swift")]
                        )

                        // Expand the macro to produce a new source file with the
                        // result of the expansion, and ensure that it has the
                        // expected source code.
                        let transformedSF = sf.expand(macros: testMacros, in: context)

                        XCTAssertEqual(
                            transformedSF.description,
                            #"""
                            let a = (x + y, "x + y")
                            let b = ("Hello, \(name)", #""Hello, \(name)""#)
                            """#
                        )
                    }
                }

                """##
        }
    }

    private func writeMacroPluginSources(_ path: AbsolutePath) throws {
        try makeDirectories(path)

        try writePackageFile(path.appending("\(moduleName)Macro.swift")) { stream in
            stream <<< ##"""
                import SwiftCompilerPlugin
                import SwiftSyntax
                import SwiftSyntaxBuilder
                import SwiftSyntaxMacros

                /// Implementation of the `stringify` macro, which takes an expression
                /// of any type and produces a tuple containing the value of that expression
                /// and the source code that produced the value. For example
                ///
                ///     #stringify(x + y)
                ///
                ///  will expand to
                ///
                ///     (x + y, "x + y")
                public struct StringifyMacro: ExpressionMacro {
                    public static func expansion(
                        of node: some FreestandingMacroExpansionSyntax,
                        in context: some MacroExpansionContext
                    ) -> ExprSyntax {
                        guard let argument = node.argumentList.first?.expression else {
                            fatalError("compiler bug: the macro does not have any arguments")
                        }

                        return "(\(argument), \(literal: argument.description))"
                    }
                }

                @main
                struct \##(moduleName)Plugin: CompilerPlugin {
                    let providingMacros: [Macro.Type] = [
                        StringifyMacro.self,
                    ]
                }

                """##
        }
    }

    private func writeMacroClientSources(_ path: AbsolutePath) throws {
        try makeDirectories(path)

        try writePackageFile(path.appending("main.swift")) { stream in
            stream <<< ##"""
                import \##(moduleName)

                let a = 17
                let b = 25

                let (result, code) = #stringify(a + b)

                print("The value \(result) was produced by the code \"\(code)\"")

                """##
        }
    }

    private func writeTestFileStubs(testsPath: AbsolutePath) throws {
        let testModule = try AbsolutePath(validating: pkgname + Target.testModuleNameSuffix, relativeTo: testsPath)
        progressReporter?("Creating \(testModule.relative(to: destinationPath))/")
        try makeDirectories(testModule)

        let testClassFile = try AbsolutePath(validating: "\(moduleName)Tests.swift", relativeTo: testModule)
        switch packageType {
        case .empty, .buildToolPlugin, .commandPlugin, .executable, .tool: break
        case .library:
            try writeLibraryTestsFile(testClassFile)
        case .macro:
            try writeMacroTestsFile(testClassFile)
        }
    }
}

// Private helpers

private enum InitError: Swift.Error {
    case manifestAlreadyExists
}

extension InitError: CustomStringConvertible {
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            return "a manifest file already exists in this directory"
        }
    }
}

extension PackageModel.Platform {
    var manifestName: String {
        switch self {
        case .macOS:
            return "macOS"
        case .macCatalyst:
            return "macCatalyst"
        case .iOS:
            return "iOS"
        case .tvOS:
            return "tvOS"
        case .watchOS:
            return "watchOS"
        case .driverKit:
            return "DriverKit"
        default:
            fatalError("unexpected manifest name call for platform \(self)")
        }
    }
}

extension SupportedPlatform {
    var isManifestAPIAvailable: Bool {
        if platform == .macOS && self.version.major == 10 {
            guard self.version.patch == 0 else {
                return false
            }
        } else if [Platform.macOS, .macCatalyst, .iOS, .watchOS, .tvOS, .driverKit].contains(platform) {
            guard self.version.minor == 0, self.version.patch == 0 else {
                return false
            }
        } else {
            return false
        }

        switch platform {
        case .macOS where version.major == 10:
            return (10...15).contains(version.minor)
        case .macOS:
            return (11...11).contains(version.major)
        case .macCatalyst:
            return (13...14).contains(version.major)
        case .iOS:
            return (8...14).contains(version.major)
        case .tvOS:
            return (9...14).contains(version.major)
        case .watchOS:
            return (2...7).contains(version.major)
        case .driverKit:
            return (19...20).contains(version.major)

        default:
            return false
        }
    }
}
