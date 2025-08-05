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

import TSCTestSupport
import SPMBuildCore

public func expectMatch(_ value: String, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    #expect(pattern ~= value, "Expected match for '\(value)' with pattern '\(pattern)'")
}
public func expectNoMatch(_ value: String, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    #expect(!(pattern ~= value), "Expected no match for '\(value)' with pattern '\(pattern)'")
}

// Should be replaced by https://github.com/swiftlang/swift-package-manager/pull/8993/files#diff-150cbfd25c6baadfd6b02914bfa68513168ae042a0b01c89bf326b2429ba242a
// when it is merged.
public func expectFileExists(
    at path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.exists(path),
        "Files '\(path)' does not exist.",
        sourceLocation: sourceLocation,
    )
}

public func expectBuilds(
    _ path: AbsolutePath,
    configurations: Set<BuildConfiguration> = [.debug, .release],
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    file: StaticString = #file,
    line: UInt = #line,
    buildSystem: BuildSystemProvider.Kind = .native
) async {
    for conf in configurations {
        await #expect(throws: Never.self) {
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

struct InitTests {

    // MARK: TSCBasic package creation for each package type.

    @Test func initPackageEmpty() throws {
        try testWithTemporaryDirectory { tmpPath in
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
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            let version = InitPackage.newPackageToolsVersion
            let versionSpecifier = "\(version.major).\(version.minor)"
            expectMatch(manifestContents, .prefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))
            expectMatch(manifestContents, .contains(packageWithNameOnly(named: name)))
        }
    }

    @Test func initPackageExecutable() async throws {
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
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            let version = InitPackage.newPackageToolsVersion
            let versionSpecifier = "\(version.major).\(version.minor)"
            expectMatch(manifestContents, .prefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))

            #expect(try fs.getDirectoryContents(path.appending("Sources").appending("Foo")) == ["Foo.swift"])
            await expectBuilds(path, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            let binPath = path.appending(components: ".build", triple.platformBuildPathComponent, "debug")
#if os(Windows)
            expectFileExists(at: binPath.appending("Foo.exe"))
#else
            expectFileExists(at: binPath.appending("Foo"))
#endif
            expectFileExists(at: binPath.appending(components: "Modules", "Foo.swiftmodule"))
        }
    }

    @Test func initPackageExecutableCalledMain() async throws {
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

            #expect(try fs.getDirectoryContents(path.appending("Sources").appending("main")) == ["MainEntrypoint.swift"])
            await expectBuilds(path, buildSystem: .native)
        }
    }

    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool])
    func initPackageLibraryWithXCTestOnly(packageType: InitPackage.PackageType) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: packageType,
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
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            let version = InitPackage.newPackageToolsVersion
            let versionSpecifier = "\(version.major).\(version.minor)"
            expectMatch(manifestContents, .prefix("// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"))

            #expect(try fs.getDirectoryContents(path.appending("Sources").appending("Foo")) == ["Foo.swift"])

            let tests = path.appending("Tests")
            #expect(try fs.getDirectoryContents(tests).sorted() == ["FooTests"])

            let testFile = tests.appending("FooTests").appending("FooTests.swift")
            let testFileContents: String = try localFileSystem.readFileContents(testFile)
            #expect(testFileContents.hasPrefix("import XCTest"), """
                          Validates formatting of XCTest source file, in particular that it does not contain leading whitespace:
                          \(testFileContents)
                          """)
            expectMatch(testFileContents, .contains("func testExample() throws"))

            // Try building it
            await expectBuilds(path, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            expectFileExists(at: path.appending(components: ".build", triple.platformBuildPathComponent, "debug", "Modules", "Foo.swiftmodule"))
        }
    }

    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool])
    func initPackagesWithSwiftTestingOnly(packageType: InitPackage.PackageType) async throws {
        try testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: packageType,
                supportedTestingLibraries: [.swiftTesting],
                destinationPath: path,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)

            let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
            let testFileContents: String = try localFileSystem.readFileContents(testFile)
            expectMatch(testFileContents, .contains(#"import Testing"#))
            expectNoMatch(testFileContents, .contains(#"import XCTest"#))
            expectMatch(testFileContents, .contains(#"@Test func example() async throws"#))
            expectNoMatch(testFileContents, .contains("func testExample() throws"))

#if canImport(TestingDisabled)
            // Try building it
            await expectBuilds(path, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            expectFileExists(path.appending(components: ".build", triple.platformBuildPathComponent, "debug", "Modules", "Foo.swiftmodule"))
#endif
        }
    }

    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool])
    func initPackageWithBothSwiftTestingAndXCTest(packageType: InitPackage.PackageType) async throws {
        try testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: packageType,
                supportedTestingLibraries: [.swiftTesting, .xctest],
                destinationPath: path,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)

            let testFile = path.appending("Tests").appending("FooTests").appending("FooTests.swift")
            let testFileContents: String = try localFileSystem.readFileContents(testFile)
            expectMatch(testFileContents, .contains(#"import Testing"#))
            expectMatch(testFileContents, .contains(#"import XCTest"#))
            expectMatch(testFileContents, .contains(#"@Test func example() async throws"#))
            expectMatch(testFileContents, .contains("func testExample() throws"))

#if canImport(TestingDisabled)
            // Try building it
            await expectBuilds(path, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            expectFileExists(path.appending(components: ".build", triple.platformBuildPathComponent, "debug", "Modules", "Foo.swiftmodule"))
#endif
        }
    }

    @Test(arguments: [InitPackage.PackageType.library, .executable, .tool])
    func initPackageWithNoTests(packageType: InitPackage.PackageType) async throws {
        try testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("Foo")
            let name = path.basename
            try fs.createDirectory(path)

            // Create the package
            let initPackage = try InitPackage(
                name: name,
                packageType: packageType,
                supportedTestingLibraries: [],
                destinationPath: path,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            // Verify basic file system content that we expect in the package
            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            expectNoMatch(manifestContents, .contains(#".testTarget"#))

            XCTAssertNoSuchPath(path.appending("Tests"))

#if canImport(TestingDisabled)
            // Try building it
            await expectBuilds(path, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            expectFileExists(path.appending(components: ".build", triple.platformBuildPathComponent, "debug", "Modules", "Foo.swiftmodule"))
#endif
        }
    }

    @Test func initPackageCommandPlugin() throws {
        try testWithTemporaryDirectory { tmpPath in
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
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            expectMatch(manifestContents, .and(.contains(".plugin("), .contains("targets: [\"MyCommandPlugin\"]")))
            expectMatch(manifestContents, .and(.contains(".plugin("),
                                                  .and(.contains("capability: .command(intent: .custom("), .contains("verb: \"MyCommandPlugin\""))))

            // Check basic content that we expect in the plugin source file
            let source = path.appending("Plugins", "MyCommandPlugin.swift")
            expectFileExists(at: source)
            let sourceContents: String = try localFileSystem.readFileContents(source)
            expectMatch(sourceContents, .contains("struct MyCommandPlugin: CommandPlugin"))
            expectMatch(sourceContents, .contains("performCommand(context: PluginContext"))
            expectMatch(sourceContents, .contains("import XcodeProjectPlugin"))
            expectMatch(sourceContents, .contains("extension MyCommandPlugin: XcodeCommandPlugin"))
            expectMatch(sourceContents, .contains("performCommand(context: XcodePluginContext"))
        }
    }

    @Test func initPackageBuildToolPlugin() throws {
        try testWithTemporaryDirectory { tmpPath in
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
            expectFileExists(at: manifest)
            let manifestContents: String = try localFileSystem.readFileContents(manifest)
            expectMatch(manifestContents, .and(.contains(".plugin("), .contains("targets: [\"MyBuildToolPlugin\"]")))
            expectMatch(manifestContents, .and(.contains(".plugin("), .contains("capability: .buildTool()")))

            // Check basic content that we expect in the plugin source file
            let source = path.appending("Plugins", "MyBuildToolPlugin.swift")
            expectFileExists(at: source)
            let sourceContents: String = try localFileSystem.readFileContents(source)
            expectMatch(sourceContents, .contains("struct MyBuildToolPlugin: BuildToolPlugin"))
            expectMatch(sourceContents, .contains("createBuildCommands(context: PluginContext"))
            expectMatch(sourceContents, .contains("import XcodeProjectPlugin"))
            expectMatch(sourceContents, .contains("extension MyBuildToolPlugin: XcodeBuildToolPlugin"))
            expectMatch(sourceContents, .contains("createBuildCommands(context: XcodePluginContext"))
        }
    }

    // MARK: Special case testing

    @Test func initPackageNonc99Directory() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertDirectoryExists(tempDirPath)

            // Create a directory with non c99name.
            let packageRoot = tempDirPath.appending("some-package")
            let packageName = packageRoot.basename
            try localFileSystem.createDirectory(packageRoot)
            XCTAssertDirectoryExists(packageRoot)

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
            await expectBuilds(packageRoot, buildSystem: .native)
            let triple = try UserToolchain.default.targetTriple
            expectFileExists(at: packageRoot.appending(components: ".build", triple.platformBuildPathComponent, "debug", "Modules", "some_package.swiftmodule"))
        }
    }

    @Test func nonC99NameExecutablePackage() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            XCTAssertDirectoryExists(tempDirPath)

            let packageRoot = tempDirPath.appending("Foo")
            try localFileSystem.createDirectory(packageRoot)
            XCTAssertDirectoryExists(packageRoot)

            // Create package with non c99name.
            let initPackage = try InitPackage(
                name: "package-name",
                packageType: .executable,
                destinationPath: packageRoot,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            await expectBuilds(packageRoot, buildSystem: .native)
        }
    }

    @Test func platforms() throws {
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
            expectMatch(contents, .contains(#"platforms: [.macOS(.v10_15), .iOS(.v12), .watchOS("2.1"), .tvOS("999.0")],"#))
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
