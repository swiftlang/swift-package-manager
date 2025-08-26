//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import SwiftParser
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import Workspace

import struct TSCBasic.ByteString
import struct TSCBasic.StringError

extension AddPackageTarget.TestHarness: @retroactive ExpressibleByArgument {}

/// The array of auxiliary files that can be added by a package editing
/// operation.
private typealias AuxiliaryFiles = [(RelativePath, SourceFileSyntax)]

extension SwiftPackageCommand {
    struct AddTarget: AsyncSwiftCommand {
        /// The type of target that can be specified on the command line.
        enum TargetType: String, Codable, ExpressibleByArgument, CaseIterable {
            case library
            case executable
            case test
            case macro
        }

        package static let configuration = CommandConfiguration(
            abstract: "Add a new target to the manifest."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The name of the new target.")
        var name: String

        @Option(help: "The type of target to add.")
        var type: TargetType = .library

        @Option(
            parsing: .upToNextOption,
            help: "A list of target dependency names."
        )
        var dependencies: [String] = []

        @Option(help: "The URL for a remote binary target.")
        var url: String?

        @Option(help: "The path to a local binary target.")
        var path: String?

        @Option(help: "The checksum for a remote binary target.")
        var checksum: String?

        @Option(
            help: "The testing library to use when generating test targets, which can be one of 'xctest', 'swift-testing', or 'none'."
        )
        var testingLibrary: AddPackageTarget.TestHarness = .default

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let workspace = try swiftCommandState.getActiveWorkspace()

            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            // Load the manifest file
            let fileSystem = workspace.fileSystem
            let manifestPath = packagePath.appending("Package.swift")
            let manifestContents: ByteString
            do {
                manifestContents = try fileSystem.readFileContents(manifestPath)
            } catch {
                throw StringError("cannot find package manifest in \(manifestPath)")
            }

            // Parse the manifest.
            let manifestSyntax = manifestContents.withData { data in
                data.withUnsafeBytes { buffer in
                    buffer.withMemoryRebound(to: UInt8.self) { buffer in
                        Parser.parse(source: buffer)
                    }
                }
            }

            // Move sources into their own folder if they're directly in `./Sources`.
            try await self.moveSingleTargetSources(
                workspace: workspace,
                packagePath: packagePath,
                verbose: !self.globalOptions.logging.quiet,
                observabilityScope: swiftCommandState.observabilityScope
            )

            // Map the target type.
            let type: PackageTarget.TargetKind = switch self.type {
            case .library: .library
            case .executable: .executable
            case .test: .test
            case .macro: .macro
            }

            // Map dependencies
            let dependencies: [PackageTarget.Dependency] = self.dependencies.map {
                .byName(name: $0)
            }

            let target = PackageTarget(
                name: name,
                type: type,
                dependencies: dependencies,
                path: path,
                url: url,
                checksum: checksum
            )
            let editResult = try AddPackageTarget.manifestRefactor(
                syntax: manifestSyntax,
                in: .init(
                    target: target,
                    testHarness: self.testingLibrary
                )
            )

            try editResult.applyEdits(
                to: fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !self.globalOptions.logging.quiet
            )

            // Once edits are applied, it's time to create new files for the target.
            try self.addAuxiliaryFiles(
                target: target,
                testHarness: self.testingLibrary,
                fileSystem: fileSystem,
                rootPath: manifestPath.parentDirectory
            )
        }

        // Check if the package has a single target with that target's sources located
        // directly in `./Sources`. If so, move the sources into a folder named after
        // the target before adding a new target.
        private func moveSingleTargetSources(
            workspace: Workspace,
            packagePath: AbsolutePath,
            verbose: Bool = false,
            observabilityScope: ObservabilityScope
        ) async throws {
            let manifest = try await workspace.loadRootManifest(
                at: packagePath,
                observabilityScope: observabilityScope
            )

            guard let target = manifest.targets.first, manifest.targets.count == 1 else {
                return
            }

            let sourcesFolder = packagePath.appending("Sources")
            let expectedTargetFolder = sourcesFolder.appending(target.name)

            let fileSystem = workspace.fileSystem
            // If there is one target then pull its name out and use that to look for a folder in `Sources/TargetName`.
            // If the folder doesn't exist then we know we have a single target package and we need to migrate files
            // into this folder before we can add a new target.
            if !fileSystem.isDirectory(expectedTargetFolder) {
                if verbose {
                    print(
                        """
                        Moving existing files from \(
                            sourcesFolder.relative(to: packagePath)
                        ) to \(
                            expectedTargetFolder.relative(to: packagePath)
                        )...
                        """,
                        terminator: ""
                    )
                }
                let contentsToMove = try fileSystem.getDirectoryContents(sourcesFolder)
                try fileSystem.createDirectory(expectedTargetFolder)
                for file in contentsToMove {
                    let source = sourcesFolder.appending(file)
                    let destination = expectedTargetFolder.appending(file)
                    try fileSystem.move(from: source, to: destination)
                }
                if verbose {
                    print(" done.")
                }
            }
        }

        private func createAuxiliaryFile(
            fileSystem: any FileSystem,
            rootPath: AbsolutePath,
            filePath: RelativePath,
            contents: SourceFileSyntax,
            verbose: Bool = false
        ) throws {
            // If the file already exists, skip it.
            let filePath = rootPath.appending(filePath)
            if fileSystem.exists(filePath) {
                if verbose {
                    print("Skipping \(filePath.relative(to: rootPath)) because it already exists.")
                }

                return
            }

            // If the directory does not exist yet, create it.
            let fileDir = filePath.parentDirectory
            if !fileSystem.exists(fileDir) {
                if verbose {
                    print("Creating directory \(fileDir.relative(to: rootPath))...", terminator: "")
                }

                try fileSystem.createDirectory(fileDir, recursive: true)

                if verbose {
                    print(" done.")
                }
            }

            // Write the file.
            if verbose {
                print("Writing \(filePath.relative(to: rootPath))...", terminator: "")
            }

            try fileSystem.writeFileContents(
                filePath,
                string: contents.description
            )

            if verbose {
                print(" done.")
            }
        }

        private func addAuxiliaryFiles(
            target: PackageTarget,
            testHarness: AddPackageTarget.TestHarness,
            fileSystem: any FileSystem,
            rootPath: AbsolutePath
        ) throws {
            let outerDirectory: String? = switch target.type {
            case .binary, .plugin, .system: nil
            case .executable, .library, .macro: "Sources"
            case .test: "Tests"
            }

            guard let outerDirectory else {
                return
            }

            let targetDir = try RelativePath(validating: outerDirectory).appending(component: target.name)
            let sourceFilePath = targetDir.appending(component: "\(target.name).swift")

            // Introduce imports for each of the dependencies that were specified.
            var importModuleNames = target.dependencies.map {
                switch $0 {
                case .byName(let name),
                     .target(let name),
                     .product(let name, package: _):
                    name
                }
            }

            // Add appropriate test module dependencies.
            if target.type == .test {
                switch testHarness {
                case .none:
                    break

                case .xctest:
                    importModuleNames.append("XCTest")

                case .swiftTesting:
                    importModuleNames.append("Testing")
                }
            }

            let importDecls = importModuleNames.lazy.sorted().map { name in
                DeclSyntax("import \(raw: name)\n")
            }

            let imports = CodeBlockItemListSyntax {
                for importDecl in importDecls {
                    importDecl
                }
            }

            var files: AuxiliaryFiles = []
            switch target.type {
            case .binary, .plugin, .system:
                break

            case .macro:
                files.addSourceFile(
                    path: sourceFilePath,
                    sourceCode: """
                    \(imports)
                    struct \(raw: target.sanitizedName): Macro {
                        /// TODO: Implement one or more of the protocols that inherit
                        /// from Macro. The appropriate macro protocol is determined
                        /// by the "macro" declaration that \(raw: target.sanitizedName) implements.
                        /// Examples include:
                        ///     @freestanding(expression) macro --> ExpressionMacro
                        ///     @attached(member) macro         --> MemberMacro
                    }
                    """
                )

                // Add a file that introduces the main entrypoint and provided macros
                // for a macro target.
                files.addSourceFile(
                    path: targetDir.appending(component: "ProvidedMacros.swift"),
                    sourceCode: """
                    import SwiftCompilerPlugin

                    @main
                    struct \(raw: target.sanitizedName)Macros: CompilerPlugin {
                        let providingMacros: [Macro.Type] = [
                            \(raw: target.sanitizedName).self,
                        ]
                    }
                    """
                )

            case .test:
                let sourceCode: SourceFileSyntax = switch testHarness {
                case .none:
                    """
                    \(imports)
                    // Test code here
                    """

                case .xctest:
                    """
                    \(imports)
                    class \(raw: target.sanitizedName)Tests: XCTestCase {
                        func test\(raw: target.sanitizedName)() {
                            XCTAssertEqual(42, 17 + 25)
                        }
                    }
                    """

                case .swiftTesting:
                    """
                    \(imports)
                    @Suite
                    struct \(raw: target.sanitizedName)Tests {
                        @Test("\(raw: target.sanitizedName) tests")
                        func example() {
                            #expect(42 == 17 + 25)
                        }
                    }
                    """
                }

                files.addSourceFile(path: sourceFilePath, sourceCode: sourceCode)

            case .library:
                files.addSourceFile(
                    path: sourceFilePath,
                    sourceCode: """
                    \(imports)
                    """
                )

            case .executable:
                files.addSourceFile(
                    path: sourceFilePath,
                    sourceCode: """
                    \(imports)
                    @main
                    struct \(raw: target.sanitizedName)Main {
                        static func main() {
                            print("Hello, world")
                        }
                    }
                    """
                )
            }

            for (file, sourceCode) in files {
                try self.createAuxiliaryFile(
                    fileSystem: fileSystem,
                    rootPath: rootPath,
                    filePath: file,
                    contents: sourceCode,
                    verbose: !self.globalOptions.logging.quiet
                )
            }
        }
    }
}

extension AuxiliaryFiles {
    /// Add a source file to the list of auxiliary files.
    fileprivate mutating func addSourceFile(
        path: RelativePath,
        sourceCode: SourceFileSyntax
    ) {
        self.append((path, sourceCode))
    }
}
