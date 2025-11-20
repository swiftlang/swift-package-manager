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

import Basics
import _InternalTestSupport
import PackageModel
import Workspace
import Testing
import SPMBuildCore

/// Tests for the `InitPackage` functionality, which creates new Swift packages with different configurations.
struct InitTests {
    /// The target triple for the current platform, used to locate build products.
    /// We instantiate this once lazily because it is not thread safe, and multiple tests
    /// running in parallel can cause a crash.
    static let targetTriple: Triple = {
        do {
            return try UserToolchain.default.targetTriple
        } catch {
            fatalError("Failed to determine target triple: \(error)")
        }
    }()

    // MARK: - Helper Methods

    /// Asserts that the package under test builds successfully.
    public func expectBuilds(
        _ path: AbsolutePath,
        buildSystem: BuildSystemProvider.Kind,
        configurations: Set<BuildConfiguration> = [.debug, .release],
        extraArgs: [String] = [],
        Xcc: [String] = [],
        Xld: [String] = [],
        Xswiftc: [String] = [],
        env: Environment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async {
        for conf in configurations {
            await #expect(throws: Never.self, sourceLocation: sourceLocation) {
                try await executeSwiftBuild(
                    path,
                    configuration: conf,
                    extraArgs: extraArgs,
                    Xcc: Xcc,
                    Xld: Xld,
                    Xswiftc: Xswiftc,
                    env: env,
                    buildSystem: buildSystem
                )
            }
        }
    }

    /// Creates a test package with the specified configuration and verifies its structure.
    private func createAndVerifyPackage(
        packageType: InitPackage.PackageType,
        name: String = "Foo",
        supportedTestingLibraries: Set<TestingLibrary> = [.xctest],
        buildSystem: BuildSystemProvider.Kind? = nil,
        buildConfiguration: BuildConfiguration = .debug,
        customVerification: ((AbsolutePath, String) throws -> Void)? = nil,
        function: StaticString = #function
    ) async throws {
        return try await testWithTemporaryDirectory(function: function) { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending(name)
            let packageName = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: packageName,
                packageType: packageType,
                supportedTestingLibraries: supportedTestingLibraries,
                destinationPath: path,
                fileSystem: fs
            )
            var progressMessages = [String]()
            initPackage.progressReporter = { message in
                progressMessages.append(message)
            }
            try initPackage.writePackageStructure()

            #expect(progressMessages.count > 0, "Expected progress messages during package creation")

            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)

            let manifestContents: String = try fs.readFileContents(manifest)
            let version = InitPackage.newPackageToolsVersion
            let versionSpecifier = "\(version.major).\(version.minor)"
            #expect(manifestContents.hasPrefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))

            if !supportedTestingLibraries.isEmpty {
                #expect(manifestContents.contains(".testTarget("))
            }

            if let buildSystem = buildSystem {
                await expectBuilds(path, buildSystem: buildSystem, configurations: Set([buildConfiguration]))

                try verifyBuildProducts(for: packageType, at: path, name: packageName, buildSystem: buildSystem, buildConfiguration: buildConfiguration)
            }

            try customVerification?(path, packageName)
        }
    }

    /// Verifies that the expected build products exist for a package.
    private func verifyBuildProducts(
        for packageType: InitPackage.PackageType,
        at path: AbsolutePath,
        name: String,
        buildSystem: BuildSystemProvider.Kind,
        buildConfiguration: BuildConfiguration
    ) throws {
        let expectedPath = path.appending(components: try buildSystem.binPath(for: buildConfiguration, triple: Self.targetTriple.platformBuildPathComponent))

        switch packageType {
        case .library:
            if buildSystem == .native {
                expectFileExists(at: expectedPath.appending("Modules", "\(name).swiftmodule"))
            } else {
                expectFileExists(at: expectedPath.appending("\(name).swiftmodule"))
            }
        case .executable, .tool:
            expectFileExists(at: expectedPath.appending(executableName(name)))
        case .empty, .buildToolPlugin, .commandPlugin, .macro:
            Issue.record("Only library, executable, and tool packages have specific build products to verify.")
            break
        }
    }

    /// Verifies the test file contents for a package.
    private func verifyTestFileContents(
        at path: AbsolutePath,
        name: String,
        hasSwiftTesting: Bool,
        hasXCTest: Bool
    ) throws {
        let testFile = path.appending("Tests").appending("\(name)Tests").appending("\(name)Tests.swift")
        let testFileContents: String = try localFileSystem.readFileContents(testFile)

        if hasSwiftTesting {
            #expect(testFileContents.contains(#"import Testing"#))
            #expect(testFileContents.contains(#"@Test func"#))
        }

        if hasXCTest {
            #expect(testFileContents.contains(#"import XCTest"#))
            #expect(testFileContents.contains("func test"))
        }
    }

    /// Verifies plugin package contents.
    private func verifyPluginPackage(
        at path: AbsolutePath,
        name: String,
        isCommandPlugin: Bool
    ) throws {
        let manifest = path.appending("Package.swift")
        try requireFileExists(at: manifest)
        let manifestContents: String = try localFileSystem.readFileContents(manifest)

        // Verify manifest contents
        #expect(manifestContents.contains(".plugin(") && manifestContents.contains("targets: [\"\(name)\"]"))

        if isCommandPlugin {
            #expect(
                manifestContents.contains(".plugin(") &&
                manifestContents.contains("capability: .command(intent: .custom(") &&
                manifestContents.contains("verb: \"\(name)\"")
            )
        } else {
            #expect(manifestContents.contains(".plugin(") && manifestContents.contains("capability: .buildTool()"))
        }

        // Verify source file
        let source = path.appending("Plugins", "\(name).swift")
        try requireFileExists(at: source)
        let sourceContents: String = try localFileSystem.readFileContents(source)

        if isCommandPlugin {
            #expect(sourceContents.contains("struct \(name): CommandPlugin"))
            #expect(sourceContents.contains("performCommand(context: PluginContext"))
        } else {
            #expect(sourceContents.contains("struct \(name): BuildToolPlugin"))
            #expect(sourceContents.contains("createBuildCommands(context: PluginContext"))
        }

        // Both plugin types should have Xcode extensions
        #expect(sourceContents.contains("import XcodeProjectPlugin"))
        if isCommandPlugin {
            #expect(sourceContents.contains("extension \(name): XcodeCommandPlugin"))
            #expect(sourceContents.contains("performCommand(context: XcodePluginContext"))
        } else {
            #expect(sourceContents.contains("extension \(name): XcodeBuildToolPlugin"))
            #expect(sourceContents.contains("createBuildCommands(context: XcodePluginContext"))
        }
    }

    // MARK: - Package Type Tests

    /// Tests creating an empty package.
    @Test func initPackageEmpty() throws {
        Task {
            try await createAndVerifyPackage(
            packageType: .empty,
            supportedTestingLibraries: [],
            customVerification: { path, name in
                let manifestContents: String = try localFileSystem.readFileContents(path.appending("Package.swift"))
                #expect(manifestContents.contains(packageWithNameOnly(named: name)))
            })
        }
    }

    /// Tests creating an executable package with different build systems.
    @Test(arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageExecutable(data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: .executable,
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, name in
                let directoryContents = try localFileSystem.getDirectoryContents(path.appending("Sources").appending(name))
                #expect(directoryContents == ["\(name).swift"])
            }
        )
    }

    /// Tests creating an executable package named "main".
    @Test(arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageExecutableCalledMain(data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: .executable,
            name: "main",
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, _ in
                let directoryContents = try localFileSystem.getDirectoryContents(path.appending("Sources").appending("main"))
                #expect(directoryContents == ["MainEntrypoint.swift"])
            }
        )
    }

    /// Tests creating packages with XCTest only.
    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool], getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageLibraryWithXCTestOnly(packageType: InitPackage.PackageType, data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: packageType,
            supportedTestingLibraries: [.xctest],
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, name in
                #expect(
                    try localFileSystem.getDirectoryContents(path.appending("Sources").appending(name)) == ["\(name).swift"],
                    "Expected single source file in Sources/\(name) directory"
                )

                let tests = path.appending("Tests")
                #expect(
                    try localFileSystem.getDirectoryContents(tests).sorted() == ["\(name)Tests"],
                    "Expected single test directory"
                )

                try verifyTestFileContents(at: path, name: name, hasSwiftTesting: false, hasXCTest: true)
            }
        )
    }

    /// Tests creating packages with Swift Testing only.
    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool], getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackagesWithSwiftTestingOnly(packageType: InitPackage.PackageType, data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: packageType,
            supportedTestingLibraries: [.swiftTesting],
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, name in
                try verifyTestFileContents(at: path, name: name, hasSwiftTesting: true, hasXCTest: false)
                let binPath = try data.buildSystem.binPath(for: data.config, triple: Self.targetTriple.platformBuildPathComponent)
                let swiftModule = "\(name).swiftmodule"
                let expectedPath = path
                    .appending(components: binPath)
                    .appending(components: data.buildSystem == .native ? ["Modules", swiftModule] : [swiftModule])

                expectFileExists(at: expectedPath)
            }
        )
    }

    /// Tests creating packages with both Swift Testing and XCTest.
    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool], getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageWithBothSwiftTestingAndXCTest(packageType: InitPackage.PackageType, data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: packageType,
            supportedTestingLibraries: [.swiftTesting, .xctest],
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, name in
                try verifyTestFileContents(at: path, name: name, hasSwiftTesting: true, hasXCTest: true)
                let binPath = try data.buildSystem.binPath(for: data.config, triple: Self.targetTriple.platformBuildPathComponent)
                let swiftModule = "\(name).swiftmodule"
                let expectedPath = path
                    .appending(components: binPath)
                    .appending(components: data.buildSystem == .native ? ["Modules", swiftModule] : [swiftModule])

                expectFileExists(at: expectedPath)
            }
        )
    }

    /// Tests creating packages with no testing libraries.
    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool], getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageWithNoTests(packageType: InitPackage.PackageType, data: BuildData) async throws {
        try await createAndVerifyPackage(
            packageType: packageType,
            supportedTestingLibraries: [],
            buildSystem: data.buildSystem,
            buildConfiguration: data.config,
            customVerification: { path, name in
                let manifestContents: String = try localFileSystem.readFileContents(path.appending("Package.swift"))
                #expect(!manifestContents.contains(#".testTarget"#))

                expectDirectoryDoesNotExist(at: path.appending("Tests"))

                let binPath = try data.buildSystem.binPath(for: data.config, triple: Self.targetTriple.platformBuildPathComponent)
                let swiftModule = "\(name).swiftmodule"
                let expectedPath = path
                    .appending(components: binPath)
                    .appending(components: data.buildSystem == .native ? ["Modules", swiftModule] : [swiftModule])

                expectFileExists(at: expectedPath)
            }
        )
    }

    /// Tests creating a command plugin package.
    @Test func initPackageCommandPlugin() async throws {
        try await createAndVerifyPackage(
            packageType: .commandPlugin,
            name: "MyCommandPlugin",
            supportedTestingLibraries: [],
            customVerification: { path, name in
                try verifyPluginPackage(at: path, name: name, isCommandPlugin: true)
            }
        )
    }

    /// Tests creating a build tool plugin package.
    @Test func initPackageBuildToolPlugin() async throws {
        try await createAndVerifyPackage(
            packageType: .buildToolPlugin,
            name: "MyBuildToolPlugin",
            supportedTestingLibraries: [],
            customVerification: { path, name in
                try verifyPluginPackage(at: path, name: name, isCommandPlugin: false)
            }
        )
    }

    // MARK: - Special Case Tests

    /// Tests creating a package in a directory with a non-C99 compliant name.
    @Test(arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms))
    func initPackageNonc99Directory(data: BuildData) async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
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
            initPackage.progressReporter = { _ in }
            try initPackage.writePackageStructure()

            // Try building it.
            await expectBuilds(packageRoot, buildSystem: data.buildSystem, configurations: [data.config])

            // Assert that the expected build products exist
            let binPath = try data.buildSystem.binPath(for: data.config, triple: Self.targetTriple.platformBuildPathComponent)
            let expectedPath = packageRoot.appending(components: binPath)

            // Verify the module name is properly mangled
            switch data.buildSystem {
            case .native: expectFileExists(at: expectedPath.appending("Modules", "some_package.swiftmodule"))
            case .swiftbuild: expectFileExists(at: expectedPath.appending("some_package.swiftmodule"))
            case .xcode: Issue.record("Not implemented")
            }
        }
    }

    /// Tests creating a package with a non-C99 compliant name.
    @Test(arguments: SupportedBuildSystemOnPlatform)
    func nonC99NameExecutablePackage(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            let packageRoot = tempDirPath.appending("Foo")
            try localFileSystem.createDirectory(packageRoot)
            expectDirectoryExists(at: packageRoot)

            // Create package with non c99name.
            let initPackage = try InitPackage(
                name: "Foo",
                packageType: .executable,
                destinationPath: packageRoot,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            await expectBuilds(packageRoot, buildSystem: buildSystem)
        }
    }

    /// Tests creating a package with custom platform requirements.
    @Test func platforms() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            // Define custom platform requirements
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

            // Create the package with custom options
            let initPackage = try InitPackage(
                name: "Foo",
                options: options,
                destinationPath: packageRoot,
                installedSwiftPMConfiguration: .default,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify platform requirements are correctly included in the manifest
            let contents: String = try localFileSystem.readFileContents(packageRoot.appending("Package.swift"))
            #expect(contents.contains(#"platforms: [.macOS(.v10_15), .iOS(.v12), .watchOS("2.1"), .tvOS("999.0")],"#))
        }
    }

    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool])
    func includesSwiftLanguageMode(packageType: InitPackage.PackageType) throws {
        try testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("testInitPackageIncludesSwiftLanguageMode")
            let name = path.basename
            try fs.createDirectory(path)

            // Create a library package
            let initPackage = try InitPackage(
                name: name,
                packageType: packageType,
                supportedTestingLibraries: [],
                destinationPath: path,
                installedSwiftPMConfiguration: .default,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify the manifest includes Swift language mode
            let manifest = path.appending("Package.swift")
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            XCTAssertMatch(manifestContents, .contains("swiftLanguageModes: [.v6]"))
        }
    }

    // MARK: - Helper Methods for Package Content

    /// Creates a simple package manifest with just the name.
    /// - Parameter name: The name of the package
    /// - Returns: A string containing the package manifest
    private func packageWithNameOnly(named name: String) -> String {
        return """
        let package = Package(
            name: "\(name)"
        )
        """
    }

    /// Creates a package manifest with name and dependencies section.
    /// - Parameter name: The name of the package
    /// - Returns: A string containing the package manifest
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
