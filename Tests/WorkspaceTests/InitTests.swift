//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
import PackageModel
import Workspace
import Testing

import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .tags(
        .FunctionalArea.Workspace,
    ),
)
struct InitTests {

    // MARK: TSCBasic package creation for each package type.

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageEmpty() throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: .empty,
                destinationPath: path,
                fileSystem: localFileSystem
            )
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            // Not picky about the specific progress messages, just checking that we got some.
            #expect(progressMessages.count > 0)

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            try requireFileExists(at: manifest)

            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            let version = InitPackage.newPackageToolsVersion
            let versionSpecifier = "\(version.major).\(version.minor)"
            #expect(manifestContents.hasPrefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))
            #expect(manifestContents.contains(packageWithNameOnly(named: name)))
        }
    }

    @Suite(
        .serialized, // Crash occurred when executed in parallel.  Needs investigation
        .tags(
            .TestSize.large,
        ),
    )
    struct InitTestsThatPerformABuild {
        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageExecutable(
            buildData: BuildData,
        ) async throws  {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .executable,
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                var progressMessages = [String]()
                initPackage.progressReporter = { message in
                    progressMessages.append(message)
                }
                try initPackage.writePackageStructure()

                // Not picky about the specific progress messages, just checking that we got some.
                #expect(progressMessages.count > 0)

                // Verify basic file system content that we expect in the package
                let manifest = path.appending("Package.swift")
                try requireFileExists(at: manifest)

                let manifestContents: String = try localFileSystem.readFileContents(manifest)
                let version = InitPackage.newPackageToolsVersion
                let versionSpecifier = "\(version.major).\(version.minor)"
                #expect(manifestContents.hasPrefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))

                #expect(try fs.getDirectoryContents(path.appending("Sources").appending("Foo")) == ["Foo.swift"])
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let binPath = try path.appending(components: buildSystem.binPath(for: configuration))
                expectFileExists(at: binPath.appending(executableName("Foo")))
                let expectedOutput: [String]
                switch buildSystem {
                    case .native:
                    expectedOutput = ["Modules", "Foo.swiftmodule"]
                    case .swiftbuild:
                    expectedOutput = ["Foo.swiftmodule"]
                    case .xcode:
                    expectedOutput = ["Foo.swiftmodule"]
                    Issue.record("Test expectation is not implemented")
                }
                let expectedFile = binPath.appending(components: expectedOutput)

                expectFileExists(at: expectedFile)
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageExecutableCalledMain(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("main")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .executable,
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                try initPackage.writePackageStructure()

                let contents = try fs.getDirectoryContents(path.appending("Sources").appending("main"))
                try #require(contents == ["MainEntrypoint.swift"])
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageLibraryWithXCTestOnly(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .library,
                    supportedTestingLibraries: [.xctest],
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                var progressMessages = [String]()
                initPackage.progressReporter = { message in
                    progressMessages.append(message)
                }
                try initPackage.writePackageStructure()

                // Not picky about the specific progress messages, just checking that we got some.
                #expect(progressMessages.count > 0)

                // Verify basic file system content that we expect in the package
                let manifest = path.appending("Package.swift")
                try requireFileExists(at:  manifest)
                let manifestContents: String = try localFileSystem.readFileContents(manifest)
                let version = InitPackage.newPackageToolsVersion
                let versionSpecifier = "\(version.major).\(version.minor)"
                #expect(manifestContents.hasPrefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))

                #expect(try fs.getDirectoryContents(path.appending("Sources").appending("Foo")) == ["Foo.swift"])

                let tests = path.appending("Tests")
                #expect(try fs.getDirectoryContents(tests).sorted() == ["FooTests"])

                let testFile = tests.appending("FooTests").appending("FooTests.swift")
                let testFileContents: String = try localFileSystem.readFileContents(testFile)
                #expect(testFileContents.hasPrefix("import XCTest"), """
                            Validates formatting of XCTest source file, in particular that it does not contain leading whitespace:
                            \(testFileContents)
                            """)
                #expect(testFileContents.contains("func testExample() throws"))

                // Try building it
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let expectedOutput: [String]
                switch buildSystem {
                    case .native:
                    expectedOutput = ["Modules", "Foo.swiftmodule"]
                    case .swiftbuild:
                    expectedOutput = ["Foo.swiftmodule"]
                    case .xcode:
                    expectedOutput = ["Foo.swiftmodule"]
                    Issue.record("Test expectation is not implemented")
                }
                let expectedFile = try path.appending(components: buildSystem.binPath(for: configuration) + expectedOutput)
                expectFileExists(at: expectedFile)
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageLibraryWithSwiftTestingOnly(
            buildData: BuildData,
        ) async throws  {

            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try withTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .library,
                    supportedTestingLibraries: [.swiftTesting],
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                try initPackage.writePackageStructure()

                // Verify basic file system content that we expect in the package
                let manifest = path.appending("Package.swift")
                try requireFileExists(at: manifest)

                let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
                let testFileContents: String = try localFileSystem.readFileContents(testFile)
                #expect(testFileContents.contains(#"import Testing"#))
                #expect(!testFileContents.contains(#"import XCTest"#))
                #expect(testFileContents.contains(#"@Test func example() async throws"#))
                #expect(!testFileContents.contains("func testExample() throws"))

    #if canImport(TestingDisabled)
                // Try building it
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let triple = try UserToolchain.default.targetTriple
                expectFileExists(at: path.appending(components: buildSystem.binPath(for: configuration) + ["Modules", "Foo.swiftmodule"]))
    #endif
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageLibraryWithBothSwiftTestingAndXCTest(
            buildData: BuildData,
        ) async throws  {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try withTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .library,
                    supportedTestingLibraries: [.swiftTesting, .xctest],
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                try initPackage.writePackageStructure()

                // Verify basic file system content that we expect in the package
                let manifest = path.appending("Package.swift")
                try requireFileExists(at: manifest)

                let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
                let testFileContents: String = try localFileSystem.readFileContents(testFile)
                #expect(testFileContents.contains(#"import Testing"#))
                #expect(testFileContents.contains(#"import XCTest"#))
                #expect(testFileContents.contains(#"@Test func example() async throws"#))
                #expect(testFileContents.contains("func testExample() throws"))

    #if canImport(TestingDisabled)
                // Try building it
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let triple = try UserToolchain.default.targetTriple
                expectFileExists(at: path.appending(components: buildSystem.binPath(for: configuration) + ["Modules", "Foo.swiftmodule"]))
    #endif
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageLibraryWithNoTests(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try withTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                let name = path.basename
                try fs.createDirectory(path)

                // Create the package
                let initPackage = try InitPackage(
                    name: name,
                    packageType: .library,
                    supportedTestingLibraries: [],
                    destinationPath: path,
                    fileSystem: localFileSystem
                )
                try initPackage.writePackageStructure()

                // Verify basic file system content that we expect in the package
                let manifest = path.appending("Package.swift")
                try requireFileExists(at: manifest)

                let manifestContents: String = try localFileSystem.readFileContents(manifest)
                #expect(!manifestContents.contains(#".testTarget"#))

                expectFileDoesNotExists(at: path.appending("Tests"))

    #if canImport(TestingDisabled)
                // Try building it
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let triple = try UserToolchain.default.targetTriple
                expectFileExists(at: path.appending(components: ".build", triple.platformBuildPathComponent, configuration.dirname, "Modules", "Foo.swiftmodule"))
    #endif
            }
        }

        // MARK: Special case testing

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func initPackageNonc99Directory(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
                expectDirectoryExists(at: tempDirPath)

                // Create a directory with non c99name.
                let packageRoot = tempDirPath.appending("some-package")
                let packageName = packageRoot.basename
                try localFileSystem.createDirectory(packageRoot)
                expectDirectoryExists(at: packageRoot)

                // Create the package
                let initPackage = try InitPackage(
                    name: packageName,
                    packageType: .library,
                    destinationPath: packageRoot,
                    fileSystem: localFileSystem
                )
                initPackage.progressReporter = { message in }
                try initPackage.writePackageStructure()

                // Try building it.
                try await executeSwiftBuild(
                    packageRoot,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )

                let expectedFile: AbsolutePath
                switch buildSystem {
                    case .native:
                    expectedFile = try packageRoot.appending(components: buildSystem.binPath(for: configuration) + ["Modules", "some_package.swiftmodule"])
                    case .swiftbuild:
                    expectedFile = try packageRoot.appending(components: buildSystem.binPath(for: configuration) + [ "some_package.swiftmodule"])
                    case .xcode:
                    expectedFile = try packageRoot.appending(components: buildSystem.binPath(for: configuration) + [ "some_package.swiftmodule"])
                    Issue.record("Test expectation is not implemented")
                }

                expectFileExists(at: expectedFile)
            }
        }

        @Test(
            .tags(
                .Feature.Command.Build,
            ),
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
            arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
        )
        func nonC99NameExecutablePackage(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
                expectDirectoryExists(at: tempDirPath)

                let packageRoot = tempDirPath.appending("Foo")
                try localFileSystem.createDirectory(packageRoot)
                expectDirectoryExists(at: packageRoot)

                // Create package with non c99name.
                let initPackage = try InitPackage(
                    name: "package-name",
                    packageType: .executable,
                    destinationPath: packageRoot,
                    fileSystem: localFileSystem
                )
                try initPackage.writePackageStructure()

                try await executeSwiftBuild(
                    packageRoot,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        }

    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageExecutableWithSwiftTesting() async throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)
            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: .executable,
                supportedTestingLibraries: [.swiftTesting],
                destinationPath: path,
                fileSystem: localFileSystem
            )

            try initPackage.writePackageStructure()
            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            try requireFileExists(at: manifest)

            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            #expect(manifestContents.contains(".testTarget("))
            let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
            let testFileContents: String = try localFileSystem.readFileContents(testFile)
            #expect(testFileContents.contains(#"import Testing"#))
            #expect(!testFileContents.contains(#"import XCTest"#))
            #expect(testFileContents.contains(#"@Test func example() async throws"#))
            #expect(!testFileContents.contains("func testExample() throws"))
        }
    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageToolWithSwiftTesting() async throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)
            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: .tool,
                supportedTestingLibraries: [.swiftTesting],
                destinationPath: path,
                fileSystem: localFileSystem
            )

            try initPackage.writePackageStructure()
            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            try requireFileExists(at: manifest)

            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            #expect(manifestContents.contains(".testTarget("))
            let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
            let testFileContents: String = try localFileSystem.readFileContents(testFile)
            #expect(testFileContents.contains(#"import Testing"#))
            #expect(!testFileContents.contains(#"import XCTest"#))
            #expect(testFileContents.contains(#"@Test func example() async throws"#))
            #expect(!testFileContents.contains("func testExample() throws"))
        }
    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageCommandPlugin() throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("MyCommandPlugin")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            try InitPackage(
                name: name,
                packageType: .commandPlugin,
                destinationPath: path,
                fileSystem: localFileSystem
            ).writePackageStructure()

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            try requireFileExists(at: manifest)

            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            #expect(manifestContents.contains(".plugin(") && manifestContents.contains("targets: [\"MyCommandPlugin\"]"))
            #expect(manifestContents.contains(".plugin(") &&
                   manifestContents.contains("capability: .command(intent: .custom(") &&
                   manifestContents.contains("verb: \"MyCommandPlugin\""))

            // Check basic content that we expect in the plugin source file
            let source = path.appending("Plugins", "MyCommandPlugin.swift")
            expectFileExists(at: source)
            let sourceContents: String = try localFileSystem.readFileContents(source)
            #expect(sourceContents.contains("struct MyCommandPlugin: CommandPlugin"))
            #expect(sourceContents.contains("performCommand(context: PluginContext"))
            #expect(sourceContents.contains("import XcodeProjectPlugin"))
            #expect(sourceContents.contains("extension MyCommandPlugin: XcodeCommandPlugin"))
            #expect(sourceContents.contains("performCommand(context: XcodePluginContext"))
        }
    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageBuildToolPlugin() throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("MyBuildToolPlugin")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            try InitPackage(
                name: name,
                packageType: .buildToolPlugin,
                destinationPath: path,
                fileSystem: localFileSystem
            ).writePackageStructure()

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            try requireFileExists(at: manifest)

            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            #expect(manifestContents.contains(".plugin(") && manifestContents.contains("targets: [\"MyBuildToolPlugin\"]"))
            #expect(manifestContents.contains(".plugin(") && manifestContents.contains("capability: .buildTool()"))

            // Check basic content that we expect in the plugin source file
            let source = path.appending("Plugins", "MyBuildToolPlugin.swift")
            expectFileExists(at: source)
            let sourceContents: String = try localFileSystem.readFileContents(source)
            #expect(sourceContents.contains("struct MyBuildToolPlugin: BuildToolPlugin"))
            #expect(sourceContents.contains("createBuildCommands(context: PluginContext"))
            #expect(sourceContents.contains("import XcodeProjectPlugin"))
            #expect(sourceContents.contains("extension MyBuildToolPlugin: XcodeBuildToolPlugin"))
            #expect(sourceContents.contains("createBuildCommands(context: XcodePluginContext"))
        }
    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func platforms() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            var options = InitPackage.InitPackageOptions(packageType: .library, supportedTestingLibraries: [])
            options.platforms = [
                .init(platform: .macOS, version: PlatformVersion("10.15")),
                .init(platform: .iOS, version: PlatformVersion("12")),
                .init(platform: .watchOS, version: PlatformVersion("2.1")),
                .init(platform: .tvOS, version: PlatformVersion("999")),
            ]

            let packageRoot = tempDirPath.appending("Foo")
            try localFileSystem.removeFileTree(packageRoot)
            try localFileSystem.createDirectory(packageRoot)

            let initPackage = try InitPackage(
                name: "Foo",
                options: options,
                destinationPath: packageRoot,
                installedSwiftPMConfiguration: .default,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let contents: String = try localFileSystem.readFileContents(packageRoot.appending("Package.swift"))
            #expect(contents.contains(#"platforms: [.macOS(.v10_15), .iOS(.v12), .watchOS("2.1"), .tvOS("999.0")],"#))
        }
    }

    @Test(
        .tags(
            .TestSize.medium,
        ),
    )
    func initPackageIncludesSwiftLanguageMode() throws {
        try withTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("testInitPackageIncludesSwiftLanguageMode")
            let name = path.basename
            try fs.createDirectory(path)

            // Create a library package
            let initPackage = try InitPackage(
                name: name,
                packageType: .library,
                supportedTestingLibraries: [],
                destinationPath: path,
                installedSwiftPMConfiguration: .default,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify the manifest includes Swift language mode
            let manifest = path.appending("Package.swift")
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            #expect(manifestContents.contains("swiftLanguageModes: [.v6]"))
        }
    }

    private func packageWithNameOnly(named name: String) -> String {
        return """
        let package = Package(
            name: "\(name)"
        )
        """
    }

    private func packageWithNameAndDependencies(with name: String) -> String {
        return """
let package = Package(
    name: "\(name)",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ]
)
"""
    }
}
