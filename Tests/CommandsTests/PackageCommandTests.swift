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
import Foundation
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import Testing
import Workspace
import _InternalTestSupport

import class Basics.AsyncProcess
import struct SPMBuildCore.BuildSystemProvider
import typealias SPMBuildCore.CLIArguments
import class TSCBasic.BufferedOutputByteStream
import struct TSCBasic.ByteString
import enum TSCBasic.JSON

@testable import Commands
@testable import CoreCommands

@discardableResult
fileprivate func execute(
    _ args: [String] = [],
    packagePath: AbsolutePath? = nil,
    manifest: String? = nil,
    env: Environment? = nil,
    configuration: BuildConfiguration,
    buildSystem: BuildSystemProvider.Kind
) async throws -> (stdout: String, stderr: String) {
    var environment = env ?? [:]
    if let manifest, let packagePath {
        try localFileSystem.writeFileContents(packagePath.appending("Package.swift"), string: manifest)
    }

    // don't ignore local packages when caching
    environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
    return try await executeSwiftPackage(
        packagePath,
        configuration: configuration,
        extraArgs: args,
        env: environment,
        buildSystem: buildSystem,
    )
}

// Helper function to arbitrarily assert on manifest content
private func expectManifest(_ packagePath: AbsolutePath, _ callback: (String) throws -> Void) throws {
    let manifestPath = packagePath.appending("Package.swift")
    expectFileExists(at: manifestPath)
    let contents: String = try localFileSystem.readFileContents(manifestPath)
    try callback(contents)
}

// Helper function to assert content exists in the manifest
private func expectManifestContains(_ packagePath: AbsolutePath, _ expected: String) throws {
    try expectManifest(packagePath) { manifestContents in
        #expect(manifestContents.contains(expected))
    }
}

// Helper function to test adding a URL dependency and asserting the result
private func executeAddURLDependencyAndAssert(
    packagePath: AbsolutePath,
    initialManifest: String? = nil,
    url: String,
    requirementArgs: [String],
    expectedManifestString: String,
    buildData: BuildData,
) async throws {
    _ = try await execute(
        ["add-dependency", url] + requirementArgs,
        packagePath: packagePath,
        manifest: initialManifest,
        configuration: buildData.config,
        buildSystem: buildData.buildSystem,
    )
    try expectManifestContains(packagePath, expectedManifestString)
}

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.Command.Package.General,
    ),
)
struct PackageCommandTests {
    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func noParameters(
        data: BuildData,
    ) async throws {
        let stdout = try await executeSwiftPackage(
            nil,
            configuration: data.config,
            buildSystem: data.buildSystem,
        ).stdout
        #expect(stdout.contains("USAGE: swift package"))
    }

    @Test(
        .issue("rdar://131126477", relationship: .defect),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func usage(
        data: BuildData,
    ) async throws {
        await expectThrowsCommandExecutionError(
            try await executeSwiftPackage(
                nil,
                configuration: data.config,
                extraArgs: ["-halp"],
                buildSystem: data.buildSystem,
            )
        ) { error in
            #expect(error.stderr.contains("Usage: swift package"))
        }
    }

    @Test
    func seeAlso() async throws {
        let stdout = try await SwiftPM.Package.execute(["--help"]).stdout
        #expect(stdout.contains("SEE ALSO: swift build, swift run, swift test \n(Run this command without --help to see possible dynamic plugin commands.)"))
    }

    @Test
    func commandDoesNotEmitDuplicateSymbols() async throws {
        let duplicateSymbolRegex = try #require(duplicateSymbolRegex)

        let (stdout, stderr) = try await SwiftPM.Package.execute(["--help"])

        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))
    }

    @Test
    func version() async throws {
        let stdout = try await SwiftPM.Package.execute(["--version"], ).stdout
        let expectedRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(expectedRegex))
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func commandFailsSilentlyWhenFetchingPluginFails(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/Plugins/MySourceGenPlugin") { fixturePath in // Contains only build-tool-plugins, therefore would not appear in available plugin commands.
            let (stdout, _) = try await execute(
                ["--help"],
                packagePath: fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            #expect(!stdout.contains("AVAILABLE PLUGIN COMMANDS:"))
            #expect(!stdout.contains("MySourceGenBuildToolPlugin"))
            #expect(!stdout.contains("MySourceGenPrebuildPlugin"))
        }
    }

    // Have to create empty package, as in CI, --help is invoked on swiftPM, causing test to fail
    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func commandDisplaysNoAvailablePluginCommands(
        data: BuildData
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in

            let packageDir = tmpPath.appending(components: "MyPackage")

            try localFileSystem.writeFileContents(
                packageDir.appending(components: "Package.swift"),
                string:
                    """
                    // swift-tools-version: 5.9
                    // The swift-tools-version declares the minimum version of Swift required to build this package.

                    import PackageDescription

                    let package = Package(
                        name: "foo"
                    )
                    """
            )
            let (stdout, _) = try await execute(
                ["--help"],
                packagePath: packageDir,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(!stdout.contains("AVAILABLE PLUGIN COMMANDS:"))
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func commandDisplaysAvailablePluginCommands(
        data: BuildData
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            // Create a sample package with a library target, a plugin, and a local tool. It depends on a sample package which also has a tool.
            let packageDir = tmpPath.appending(components: "MyPackage")
            try localFileSystem.writeFileContents(
                packageDir.appending(components: "Package.swift"),
                string:
                    """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(
                        name: "MyPackage",
                        targets: [
                            .plugin(
                                name: "MyPlugin",
                                capability: .command(
                                    intent: .custom(verb: "mycmd", description: "What is mycmd anyway?")
                                ),
                                dependencies: [
                                    .target(name: "LocalBuiltTool"),
                                ]
                            ),
                            .executableTarget(
                                name: "LocalBuiltTool"
                            )
                        ]
                    )
                    """
            )

            try localFileSystem.writeFileContents(
                packageDir.appending(components: "Sources", "LocalBuiltTool", "main.swift"),
                string: #"print("Hello")"#
            )
            try localFileSystem.writeFileContents(
                packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                string: """
                    import PackagePlugin
                    import Foundation
                    @main
                    struct MyCommandPlugin: CommandPlugin {
                        func performCommand(
                            context: PluginContext,
                            arguments: [String]
                        ) throws {
                            print("This is MyCommandPlugin.")
                        }
                    }
                    """
            )

            let (stdout, _) = try await execute(
                ["--help"],
                packagePath: packageDir,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            #expect(stdout.contains("AVAILABLE PLUGIN COMMANDS:"))
            #expect(stdout.contains("mycmd"))
            #expect(stdout.contains("(plugin ‘MyPlugin’ in package ‘MyPackage’)"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.CompletionTool,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func completionTool(
        data: BuildData,
    ) async throws {
        let stdout = try await execute(
            ["completion-tool", "--help"],
            configuration: data.config,
            buildSystem: data.buildSystem,
        ).stdout
        #expect(stdout.contains("OVERVIEW: Command to generate shell completions."))
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Init,
        ),
    )
    struct InitHelpUsageTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initOverview(
            data: BuildData,
        ) async throws {
            let stdout = try await execute(
                ["init", "--help"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            ).stdout
            #expect(stdout.contains("OVERVIEW: Initialize a new package"))
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initUsage(
            data: BuildData,
        ) async throws {
            let stdout = try await execute(
                ["init", "--help"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            ).stdout
            #expect(stdout.contains("USAGE: swift package init [--type <type>] "))
            #expect(stdout.contains(" [--name <name>]"))
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initOptionsHelp(
            data: BuildData,
        ) async throws {
            let stdout = try await execute(
                ["init", "--help"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            ).stdout
            #expect(stdout.contains("OPTIONS:"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.Plugin,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func plugin(
        data: BuildData,
    ) async throws {
        await expectThrowsCommandExecutionError(
            try await execute(
                ["plugin"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        ) { error in
            #expect(error.stderr.contains("error: Missing expected plugin command"))
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func unknownOption(
        data: BuildData,
    ) async throws {
        await expectThrowsCommandExecutionError(
            try await execute(
                ["--foo"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        ) { error in
            #expect(error.stderr.contains("error: Unknown option '--foo'"))
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func unknownSubcommand(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/ExeTest") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await execute(
                    ["foo"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                #expect(error.stderr.contains("Unknown subcommand or plugin name ‘foo’"))
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
    )
    struct ResolveCommandTests {
        @Suite(
            .tags(
                .Feature.NetRc,
            ),
        )
        struct NetRcTests {
            @Test(
                arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            )
            func netrc(
                data: BuildData,
            ) async throws {
                try await fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
                    // --enable-netrc flag
                    try await execute(
                        ["resolve", "--enable-netrc"],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // --disable-netrc flag
                    try await execute(
                        ["resolve", "--disable-netrc"],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // --enable-netrc and --disable-netrc flags
                    await expectThrowsCommandExecutionError(
                        try await execute(
                            ["resolve", "--enable-netrc", "--disable-netrc"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        #expect(
                            error.stderr.contains(
                                "Value to be set with flag '--disable-netrc' had already been set with flag '--enable-netrc'"
                            )
                        )
                    }
                }
            }

            @Test(
                arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            )
            func netrcFile(
                data: BuildData,
            ) async throws {
                try await fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
                    let fs = localFileSystem
                    let netrcPath = fixturePath.appending(".netrc")
                    try fs.writeFileContents(
                        netrcPath,
                        string: "machine mymachine.labkey.org login user@labkey.org password mypassword"
                    )

                    // valid .netrc file path
                    try await execute(
                        ["resolve", "--netrc-file", netrcPath.pathString],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // valid .netrc file path with --disable-netrc option
                    await expectThrowsCommandExecutionError(
                        try await execute(
                            ["resolve", "--netrc-file", netrcPath.pathString, "--disable-netrc"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        #expect(
                            error.stderr.contains("'--disable-netrc' and '--netrc-file' are mutually exclusive")
                        )
                    }

                    // invalid .netrc file path
                    let errorRegex = try Regex(#".* Did not find netrc file at ([A-Z]:\\|\/)foo.*"#)
                    await expectThrowsCommandExecutionError(
                        try await execute(
                            ["resolve", "--netrc-file", "/foo"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        #expect(error.stderr.contains(errorRegex))
                    }

                    // invalid .netrc file path with --disable-netrc option
                    await expectThrowsCommandExecutionError(
                        try await execute(
                            ["resolve", "--netrc-file", "/foo", "--disable-netrc"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        #expect(
                            error.stderr.contains("'--disable-netrc' and '--netrc-file' are mutually exclusive")
                        )
                    }
                }
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Reset,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func enableDisableCache(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                let repositoriesPath = packageRoot.appending(components: ".build", "repositories")
                let cachePath = fixturePath.appending("cache")
                let repositoriesCachePath = cachePath.appending("repositories")

                do {
                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // we have to check for the prefix here since the hash value changes because spm sees the `prefix`
                    // directory `/var/...` as `/private/var/...`.
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )

                    // Remove .build folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // Perform another cache this time from the cache
                    _ = try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )

                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    // Perform another fetch
                    _ = try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                }

                do {
                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    try await execute(
                        ["resolve", "--disable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // we have to check for the prefix here since the hash value changes because spm sees the `prefix`
                    // directory `/var/...` as `/private/var/...`.
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(!localFileSystem.exists(repositoriesCachePath))
                }

                do {
                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    let (_, _) = try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // we have to check for the prefix here since the hash value changes because spm sees the `prefix`
                    // directory `/var/...` as `/private/var/...`.
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )

                    // Remove .build folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // Perform another cache this time from the cache
                    _ = try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )

                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    // Perform another fetch
                    _ = try await execute(
                        ["resolve", "--enable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                }

                do {
                    // Remove .build and cache folder
                    _ = try await execute(
                        ["reset"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    try localFileSystem.removeFileTree(cachePath)

                    let (_, _) = try await execute(
                        ["resolve", "--disable-dependency-cache", "--cache-path", cachePath.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // we have to check for the prefix here since the hash value changes because spm sees the `prefix`
                    // directory `/var/...` as `/private/var/...`.
                    #expect(
                        try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                            $0.hasPrefix("Foo-")
                        }
                    )
                    #expect(!localFileSystem.exists(repositoriesCachePath))
                }
            }
        }
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func resolve(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")

                // Check that `resolve` works.
                _ = try await execute(
                    ["resolve"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let path = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
                #expect(try GitRepository(path: path).getTags() == ["1.2.3"])
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Update,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func update(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")

                // Perform an initial fetch.
                _ = try await execute(
                    ["resolve"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                do {
                    let checkoutPath = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
                    let checkoutRepo = GitRepository(path: checkoutPath)
                    #expect(try checkoutRepo.getTags() == ["1.2.3"])
                    _ = try checkoutRepo.revision(forTag: "1.2.3")
                }

                // update and retag the dependency, and update.
                let repoPath = fixturePath.appending("Foo")
                let repo = GitRepository(path: repoPath)
                try localFileSystem.writeFileContents(repoPath.appending("test"), string: "test")
                try repo.stageEverything()
                try repo.commit()
                try repo.tag(name: "1.2.4")

                // we will validate it is there
                let revision = try repo.revision(forTag: "1.2.4")

                _ = try await execute(
                    ["update"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                do {
                    // We shouldn't assume package path will be same after an update so ask again for it.
                    let checkoutPath = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
                    let checkoutRepo = GitRepository(path: checkoutPath)
                    // tag may not be there, but revision should be after update
                    #expect(checkoutRepo.exists(revision: .init(identifier: revision)))
                }
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Reset,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func cache(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                let repositoriesPath = packageRoot.appending(components: ".build", "repositories")
                let cachePath = fixturePath.appending("cache")
                let repositoriesCachePath = cachePath.appending("repositories")

                // Perform an initial fetch and populate the cache
                _ = try await execute(
                    ["resolve", "--cache-path", cachePath.pathString],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                // we have to check for the prefix here since the hash value changes because spm sees the `prefix`
                // directory `/var/...` as `/private/var/...`.
                #expect(
                    try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                        $0.hasPrefix("Foo-")
                    }
                )
                #expect(
                    try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                        $0.hasPrefix("Foo-")
                    }
                )

                // Remove .build folder
                _ = try await execute(
                    ["reset"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                // Perform another cache this time from the cache
                _ = try await execute(
                    ["resolve", "--cache-path", cachePath.pathString],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(
                    try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                        $0.hasPrefix("Foo-")
                    }
                )

                // Remove .build and cache folder
                _ = try await execute(
                    ["reset"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                try localFileSystem.removeFileTree(cachePath)

                // Perform another fetch
                _ = try await execute(
                    ["resolve", "--cache-path", cachePath.pathString],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(
                    try localFileSystem.getDirectoryContents(repositoriesPath).contains {
                        $0.hasPrefix("Foo-")
                    }
                )
                #expect(
                    try localFileSystem.getDirectoryContents(repositoriesCachePath).contains {
                        $0.hasPrefix("Foo-")
                    }
                )
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Describe,
        ),
    )
    struct DescribeCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func describe(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/ExeTest") { fixturePath in
                // Generate the JSON description.
                let (jsonOutput, _) = try await execute(
                    ["describe", "--type=json"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))

                // Check that tests don't appear in the product memberships.
                #expect(json["name"]?.string == "ExeTest")
                let jsonTarget0 = try #require(json["targets"]?.array?[0])
                #expect(jsonTarget0["product_memberships"] == nil)
                let jsonTarget1 = try #require(json["targets"]?.array?[1])
                #expect(jsonTarget1["product_memberships"]?.array?[0].stringValue == "Exe")
            }

            try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
                // Generate the JSON description.
                let (jsonOutput, _) = try await execute(
                    ["describe", "--type=json"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))

                // Check that the JSON description contains what we expect it to.
                #expect(json["name"]?.string == "SwiftCMixed")
                let pathString = try #require(json["path"]?.string)
                try #expect(pathString.contains(Regex(#"^([A-Z]:\\|\/).*"#)))
                #expect(pathString.hasSuffix(AbsolutePath("/" + fixturePath.basename).pathString))
                #expect(json["targets"]?.array?.count == 3)
                let jsonTarget0 = try #require(json["targets"]?.array?[0])
                #expect(jsonTarget0["name"]?.stringValue == "SeaLib")
                #expect(jsonTarget0["c99name"]?.stringValue == "SeaLib")
                #expect(jsonTarget0["type"]?.stringValue == "library")
                #expect(jsonTarget0["module_type"]?.stringValue == "ClangTarget")
                let jsonTarget1 = try #require(json["targets"]?.array?[1])
                #expect(jsonTarget1["name"]?.stringValue == "SeaExec")
                #expect(jsonTarget1["c99name"]?.stringValue == "SeaExec")
                #expect(jsonTarget1["type"]?.stringValue == "executable")
                #expect(jsonTarget1["module_type"]?.stringValue == "SwiftTarget")
                #expect(jsonTarget1["product_memberships"]?.array?[0].stringValue == "SeaExec")
                let jsonTarget2 = try #require(json["targets"]?.array?[2])
                #expect(jsonTarget2["name"]?.stringValue == "CExec")
                #expect(jsonTarget2["c99name"]?.stringValue == "CExec")
                #expect(jsonTarget2["type"]?.stringValue == "executable")
                #expect(jsonTarget2["module_type"]?.stringValue == "ClangTarget")
                #expect(jsonTarget2["product_memberships"]?.array?[0].stringValue == "CExec")

                // Generate the text description.
                let (textOutput, _) = try await execute(
                    ["describe", "--type=text"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let textChunks = textOutput.components(separatedBy: "\n").reduce(into: [""]) {
                    chunks,
                    line in
                    // Split the text into chunks based on presence or absence of leading whitespace.
                    if line.hasPrefix(" ") == chunks[chunks.count - 1].hasPrefix(" ") {
                        chunks[chunks.count - 1].append(line + "\n")
                    } else {
                        chunks.append(line + "\n")
                    }
                }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                // Check that the text description contains what we expect it to.
                // FIXME: This is a bit inelegant, but any errors are easy to reason about.
                let textChunk0 = textChunks[0]
                #expect(textChunk0.contains("Name: SwiftCMixed"))
                try #expect(textChunk0.contains(Regex(#"Path: ([A-Z]:\\|\/)"#)))
                #expect(textChunk0.contains(AbsolutePath("/" + fixturePath.basename).pathString + "\n"))
                #expect(textChunk0.contains("Tools version: 4.2"))
                #expect(textChunk0.contains("Products:"))
                let textChunk1 = textChunks[1]
                #expect(textChunk1.contains("Name: SeaExec"))
                #expect(textChunk1.contains("Type:\n        Executable"))
                #expect(textChunk1.contains("Targets:\n        SeaExec"))
                let textChunk2 = textChunks[2]
                #expect(textChunk2.contains("Name: CExec"))
                #expect(textChunk2.contains("Type:\n        Executable"))
                #expect(textChunk2.contains("Targets:\n        CExec"))
                let textChunk3 = textChunks[3]
                #expect(textChunk3.contains("Targets:"))
                let textChunk4 = textChunks[4]
                #expect(textChunk4.contains("Name: SeaLib"))
                #expect(textChunk4.contains("C99name: SeaLib"))
                #expect(textChunk4.contains("Type: library"))
                #expect(textChunk4.contains("Module type: ClangTarget"))
                #expect(textChunk4.contains("Path: \(RelativePath("Sources/SeaLib").pathString)"))
                #expect(textChunk4.contains("Sources:\n        Foo.c"))
                let textChunk5 = textChunks[5]
                #expect(textChunk5.contains("Name: SeaExec"))
                #expect(textChunk5.contains("C99name: SeaExec"))
                #expect(textChunk5.contains("Type: executable"))
                #expect(textChunk5.contains("Module type: SwiftTarget"))
                #expect(textChunk5.contains("Path: \(RelativePath("Sources/SeaExec").pathString)"))
                #expect(textChunk5.contains("Sources:\n        main.swift"))
                let textChunk6 = textChunks[6]
                #expect(textChunk6.contains("Name: CExec"))
                #expect(textChunk6.contains("C99name: CExec"))
                #expect(textChunk6.contains("Type: executable"))
                #expect(textChunk6.contains("Module type: ClangTarget"))
                #expect(textChunk6.contains("Path: \(RelativePath("Sources/CExec").pathString)"))
                #expect(textChunk6.contains("Sources:\n        main.c"))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Describe
            ),
            .IssueWindowsRelativePathAssert,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func describeJson(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: ProcessInfo.hostOperatingSystem == .windows) {
                try await fixture(name: "DependencyResolution/External/Simple/Bar") { fixturePath in
                    // Generate the JSON description.
                    let (jsonOutput, _) = try await execute(
                        ["describe", "--type=json"],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))

                    // Check that product dependencies and memberships are as expected.
                    #expect(json["name"]?.string == "Bar")
                    let jsonTarget = try #require(json["targets"]?.array?[0])
                    #expect(jsonTarget["product_memberships"]?.array?[0].stringValue == "Bar")
                    #expect(jsonTarget["product_dependencies"]?.array?[0].stringValue == "Foo")
                    #expect(jsonTarget["target_dependencies"] == nil)
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func describePackageUsingPlugins(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/Plugins/MySourceGenPlugin") { fixturePath in
                // Generate the JSON description.
                let (stdout, _) = try await execute(
                    ["describe", "--type=json"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let json = try JSON(bytes: ByteString(encodingAsUTF8: stdout))

                // Check the contents of the JSON.
                #expect(try #require(json["name"]).string == "MySourceGenPlugin")
                let targetsArray = try #require(json["targets"]?.array)
                let buildToolPluginTarget = try #require(
                    targetsArray.first { $0["name"]?.string == "MySourceGenBuildToolPlugin" }?.dictionary
                )
                #expect(buildToolPluginTarget["module_type"]?.string == "PluginTarget")
                #expect(
                    buildToolPluginTarget["plugin_capability"]?.dictionary?["type"]?.string == "buildTool"
                )
                let prebuildPluginTarget = try #require(
                    targetsArray.first { $0["name"]?.string == "MySourceGenPrebuildPlugin" }?.dictionary
                )
                #expect(prebuildPluginTarget["module_type"]?.string == "PluginTarget")
                #expect(
                    prebuildPluginTarget["plugin_capability"]?.dictionary?["type"]?.string == "buildTool"
                )
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func dumpPackage(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/DumpPackage") { fixturePath in
            let packageRoot = fixturePath.appending("app")
            let (dumpOutput, _) = try await execute(
                ["dump-package"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case .dictionary(let contents) = json else {
                Issue.record("unexpected result")
                return
            }
            guard case .string(let name)? = contents["name"] else {
                Issue.record("unexpected name")
                return
            }
            guard case .string(let defaultLocalization)? = contents["defaultLocalization"] else {
                Issue.record("unexpected defaultLocalization")
                return
            }
            guard case .array(let platforms)? = contents["platforms"] else {
                Issue.record("unexpected platforms")
                return
            }
            #expect(name == "Dealer")
            #expect(defaultLocalization == "en")
            #expect(
                platforms == [
                    .dictionary([
                        "platformName": .string("macos"),
                        "version": .string("10.13"),
                        "options": .array([]),
                    ]),
                    .dictionary([
                        "platformName": .string("ios"),
                        "version": .string("12.0"),
                        "options": .array([]),
                    ]),
                    .dictionary([
                        "platformName": .string("tvos"),
                        "version": .string("12.0"),
                        "options": .array([]),
                    ]),
                    .dictionary([
                        "platformName": .string("watchos"),
                        "version": .string("5.0"),
                        "options": .array([]),
                    ]),
                ]
            )
            // FIXME: We should also test dependencies and targets here.
        }
    }

    @Test(
        .disabled(
            "disabling this suite.. first one to fail. due to \"couldn't determine the current working directory\""
        ),
        .tags(
            .Feature.Command.Package.DumpSymbolGraph,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8848", relationship: .defect),
        .IssueWindowsLongPath,
        .requiresSymbolgraphExtract,
        arguments: getBuildData(for: [.swiftbuild]),
        [
            true,
            false,
        ],
    )
    func dumpSymbolGraphFormatting(
        data: BuildData,
        withPrettyPrinting: Bool,
    ) async throws {
        // try XCTSkipIf(buildSystemProvider == .native && (try? UserToolchain.default.getSymbolGraphExtract()) == nil, "skipping test because the `swift-symbolgraph-extract` tools isn't available")
        try await withKnownIssue {
            try await fixture(
                name: "DependencyResolution/Internal/Simple",
                removeFixturePathOnDeinit: true
            ) { fixturePath in
                let tool = try SwiftCommandState.makeMockState(
                    options: GlobalOptions.parse(["--package-path", fixturePath.pathString])
                )
                let symbolGraphExtractorPath = try tool.getTargetToolchain().getSymbolGraphExtract()

                let arguments =
                    withPrettyPrinting ? ["dump-symbol-graph", "--pretty-print"] : ["dump-symbol-graph"]

                let result = try await execute(
                    arguments,
                    packagePath: fixturePath,
                    env: ["SWIFT_SYMBOLGRAPH_EXTRACT": symbolGraphExtractorPath.pathString],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let enumerator = try #require(
                    FileManager.default.enumerator(
                        at: URL(fileURLWithPath: fixturePath.pathString),
                        includingPropertiesForKeys: nil
                    )
                )

                var symbolGraphURLOptional: URL? = nil
                while let element = enumerator.nextObject() {
                    if let url = element as? URL, url.lastPathComponent == "Bar.symbols.json" {
                        symbolGraphURLOptional = url
                        break
                    }
                }

                let symbolGraphURL = try #require(
                    symbolGraphURLOptional,
                    "Failed to extract symbol graph: \(result.stdout)\n\(result.stderr)"
                )
                let symbolGraphData = try Data(contentsOf: symbolGraphURL)

                // Double check that it's a valid JSON
                #expect(throws: Never.self) {
                    try JSONSerialization.jsonObject(with: symbolGraphData)
                }

                let JSONText = String(decoding: symbolGraphData, as: UTF8.self)
                if withPrettyPrinting {
                    #expect(JSONText.components(separatedBy: .newlines).count > 1)
                } else {
                    #expect(JSONText.components(separatedBy: .newlines).count == 1)
                }
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild && !withPrettyPrinting)
                || (data.buildSystem == .swiftbuild && withPrettyPrinting)
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.CompletionTool,
        ),
    )
    struct CompletionToolCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func completionToolListSnippets(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/Plugins/PluginsAndSnippets") { fixturePath in
                let result = try await execute(
                    ["completion-tool", "list-snippets"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.stdout == "ContainsMain\nImportsProductTarget\nMySnippet\nmain\n")
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func completionToolListDependencies(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
                let result = try await execute(
                    ["completion-tool", "list-dependencies"],
                    packagePath: fixturePath.appending("deck-of-playing-cards-local"),
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.stdout == "playingcard\nfisheryates\n")
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func completionToolListExecutables(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let result = try await execute(
                    ["completion-tool", "list-executables"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.stdout == "exec1\nexec2\n")
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func completionToolListExecutablesDifferentNames(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/DifferentProductTargetName") { fixturePath in
                let result = try await execute(
                    ["completion-tool", "list-executables"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.stdout == "Foo\n")
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.ShowTraits,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func showTraits(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/ShowTraits") { fixturePath in
            let packageRoot = fixturePath.appending("app")
            var (textOutput, _) = try await execute(
                ["show-traits", "--format=text"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(textOutput.contains("trait1 - this trait is the default in app (default)"))
            #expect(textOutput.contains("trait2 - this trait is not the default in app"))
            #expect(!textOutput.contains("trait3"))

            var (jsonOutput, _) = try await execute(
                ["show-traits", "--format=json"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            var json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case .array(let contents) = json else {
                Issue.record("unexpected result")
                return
            }

            #expect(3 == contents.count)

            guard case let first = contents.first else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let `default`) = first else {
                Issue.record("unexpected result")
                return
            }
            #expect(`default`["name"]?.stringValue ==  "default")
            guard case .array(let enabledTraits) = `default`["enabledTraits"] else {
                Issue.record("unexpected result")
                return
            }
            #expect(enabledTraits.count == 1)
            let firstEnabledTrait = enabledTraits[0]
            #expect(firstEnabledTrait.stringValue == "trait1")

            guard case let second = contents[1] else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let trait1) = second else {
                Issue.record("unexpected result")
                return
            }
            #expect(trait1["name"]?.stringValue ==  "trait1")

            guard case let third = contents[2] else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let trait2) = third else {
                Issue.record("unexpected result")
                return
            }
            #expect(trait2["name"]?.stringValue ==  "trait2")

            // Show traits for the dependency based on its package id
            (textOutput, _) = try await execute(
                ["show-traits", "--package-id=deck-of-playing-cards", "--format=text"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(!textOutput.contains("trait1 - this trait is the default in app (default)"))
            #expect(!textOutput.contains("trait2 - this trait is not the default in app"))
            #expect(textOutput.contains("trait3"))

            (jsonOutput, _) = try await execute(
                ["show-traits", "--package-id=deck-of-playing-cards", "--format=json"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case .array(let contents) = json else {
                Issue.record("unexpected result")
                return
            }

            #expect(1 == contents.count)

            guard case let first = contents.first else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let trait3) = first else {
                Issue.record("unexpected result")
                return
            }
            #expect(trait3["name"]?.stringValue ==  "trait3")
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.ShowExecutables,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func showExecutables(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/ShowExecutables") { fixturePath in
            let packageRoot = fixturePath.appending("app")
            let (textOutput, _) = try await execute(
                ["show-executables", "--format=flatlist"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(textOutput.contains("dealer\n"))
            #expect(textOutput.contains("deck (deck-of-playing-cards)\n"))

            let (jsonOutput, _) = try await execute(
                ["show-executables", "--format=json"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case .array(let contents) = json else {
                Issue.record("unexpected result")
                return
            }

            #expect(2 == contents.count)

            guard case let first = contents.first else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let dealer) = first else {
                Issue.record("unexpected result")
                return
            }
            guard case .string(let dealerName)? = dealer["name"] else {
                Issue.record("unexpected result")
                return
            }
            #expect(dealerName == "dealer")
            if case .string(let package)? = dealer["package"] {
                Issue.record("unexpected package for dealer (should be unset): \(package)")
                return
            }

            guard case let last = contents.last else {
                Issue.record("unexpected result")
                return
            }
            guard case .dictionary(let deck) = last else {
                Issue.record("unexpected result")
                return
            }
            guard case .string(let deckName)? = deck["name"] else {
                Issue.record("unexpected result")
                return
            }
            #expect(deckName == "deck")
            if case .string(let package)? = deck["package"] {
                #expect("deck-of-playing-cards" == package)
            } else {
                Issue.record("missing package for deck")
                return
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
    )
    struct ShowDependenciesCommandTests {
        @Test(
            .tags(
                .Feature.Command.Package.ShowDependencies,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func showDependencies(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
                let packageRoot = fixturePath.appending("app")
                let (textOutput, _) = try await execute(
                    ["show-dependencies", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(textOutput.contains("FisherYates@1.2.3"))

                let (jsonOutput, _) = try await execute(
                    ["show-dependencies", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
                guard case .dictionary(let contents) = json else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "Dealer")
                guard case .string(let path)? = contents["path"] else {
                    Issue.record("unexpected result")
                    return
                }
                let actual = try resolveSymlinks(try AbsolutePath(validating: path))
                let expected = try resolveSymlinks(packageRoot)
                #expect(actual == expected)
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.ShowDependencies,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func showDependenciesWithTraits(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Traits") { fixturePath in
                let packageRoot = fixturePath.appending("Example")
                let (textOutput, _) = try await execute(
                    ["show-dependencies", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(textOutput.contains("(traits: Package3Trait3)"))

                let (jsonOutput, _) = try await execute(
                    ["show-dependencies", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
                guard case .dictionary(let contents) = json else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "TraitsExample")

                // verify the traits JSON entry lists each of the traits in the fixture
                guard case .array(let traitsProperty)? = contents["traits"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(traitsProperty.contains(.string("Package1")))
                #expect(traitsProperty.contains(.string("Package2")))
                #expect(traitsProperty.contains(.string("Package3")))
                #expect(traitsProperty.contains(.string("Package4")))
                #expect(traitsProperty.contains(.string("BuildCondition1")))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.ShowDependencies,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func showDependenciesWithTraitsGuardingDependencies(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Traits") { fixturePath in
                let packageRoot = fixturePath.appending("PackageConditionalDeps")

                // Test output with default traits
                let (textOutputDefault, _) = try await execute(
                    ["show-dependencies", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(textOutputDefault.contains("Package1@"))
                #expect(!textOutputDefault.contains("Package2"))

                let (jsonOutputDefault, _) = try await execute(
                    ["show-dependencies", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let jsonDefault = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutputDefault))
                guard case .dictionary(let contents) = jsonDefault else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "PackageConditionalDeps")

                guard case .array(let traitsProperty)? = contents["traits"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(traitsProperty.contains(.string("EnablePackage1Dep")))

                // Test output with default traits disabled
                let (textOutputDefaultDisabled, _) = try await execute(
                    ["show-dependencies", "--disable-default-traits", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(textOutputDefaultDisabled.contains("No external dependencies found"))
                #expect(!textOutputDefaultDisabled.contains("Package1"))
                #expect(!textOutputDefaultDisabled.contains("Package2"))

                let (jsonOutputDefaultDisabled, _) = try await execute(
                    ["show-dependencies", "--disable-default-traits", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let jsonDefaultDisabled = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutputDefaultDisabled))
                guard case .dictionary(let contents) = jsonDefaultDisabled else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "PackageConditionalDeps")

                guard case .array(let traitsProperty)? = contents["traits"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(traitsProperty.isEmpty)

                // Test output with overridden trait configuration
                let (textOutputPackage2Dep, _) = try await execute(
                    ["show-dependencies", "--traits", "EnablePackage2Dep", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(!textOutputPackage2Dep.contains("Package1"))
                #expect(textOutputPackage2Dep.contains("Package2@"))

                let (jsonOutputPackage2Dep, _) = try await execute(
                    ["show-dependencies", "--traits", "EnablePackage2Dep", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let jsonPackage2Dep = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutputPackage2Dep))
                guard case .dictionary(let contents) = jsonPackage2Dep else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "PackageConditionalDeps")

                guard case .array(let traitsProperty)? = contents["traits"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(traitsProperty.contains(.string("EnablePackage2Dep")))
                #expect(!traitsProperty.contains(.string("EnablePackage1Dep")))

                // Test output with all traits enabled
                let (textOutputAllTraits, _) = try await execute(
                    ["show-dependencies", "--enable-all-traits", "--format=text"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(textOutputAllTraits.contains("Package1@"))
                #expect(textOutputAllTraits.contains("Package2@"))

                let (jsonOutputAllTraits, _) = try await execute(
                    ["show-dependencies", "--enable-all-traits", "--format=json"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                let jsonAllTraits = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutputAllTraits))
                guard case .dictionary(let contents) = jsonAllTraits else {
                    Issue.record("unexpected result")
                    return
                }
                guard case .string(let name)? = contents["name"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(name == "PackageConditionalDeps")

                guard case .array(let traitsProperty)? = contents["traits"] else {
                    Issue.record("unexpected result")
                    return
                }
                #expect(traitsProperty.contains(.string("EnablePackage2Dep")))
                #expect(traitsProperty.contains(.string("EnablePackage1Dep")))

            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func showDependencies_dotFormat_sr12016(
            data: BuildData,
        ) throws {
            let fileSystem = InMemoryFileSystem(emptyFiles: [
                "/PackageA/Sources/TargetA/main.swift",
                "/PackageB/Sources/TargetB/B.swift",
                "/PackageC/Sources/TargetC/C.swift",
                "/PackageD/Sources/TargetD/D.swift",
            ])

            let manifestA = Manifest.createRootManifest(
                displayName: "PackageA",
                path: "/PackageA",
                toolsVersion: .v5_3,
                dependencies: [
                    .fileSystem(path: "/PackageB"),
                    .fileSystem(path: "/PackageC"),
                ],
                products: [
                    try .init(name: "exe", type: .executable, targets: ["TargetA"])
                ],
                targets: [
                    try .init(name: "TargetA", dependencies: ["PackageB", "PackageC"])
                ]
            )

            let manifestB = Manifest.createFileSystemManifest(
                displayName: "PackageB",
                path: "/PackageB",
                toolsVersion: .v5_3,
                dependencies: [
                    .fileSystem(path: "/PackageC"),
                    .fileSystem(path: "/PackageD"),
                ],
                products: [
                    try .init(name: "PackageB", type: .library(.dynamic), targets: ["TargetB"])
                ],
                targets: [
                    try .init(name: "TargetB", dependencies: ["PackageC", "PackageD"])
                ]
            )

            let manifestC = Manifest.createFileSystemManifest(
                displayName: "PackageC",
                path: "/PackageC",
                toolsVersion: .v5_3,
                dependencies: [
                    .fileSystem(path: "/PackageD")
                ],
                products: [
                    try .init(name: "PackageC", type: .library(.dynamic), targets: ["TargetC"])
                ],
                targets: [
                    try .init(name: "TargetC", dependencies: ["PackageD"])
                ]
            )

            let manifestD = Manifest.createFileSystemManifest(
                displayName: "PackageD",
                path: "/PackageD",
                toolsVersion: .v5_3,
                products: [
                    try .init(name: "PackageD", type: .library(.dynamic), targets: ["TargetD"])
                ],
                targets: [
                    try .init(name: "TargetD")
                ]
            )

            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadModulesGraph(
                fileSystem: fileSystem,
                manifests: [manifestA, manifestB, manifestC, manifestD],
                observabilityScope: observability.topScope
            )
            expectNoDiagnostics(observability.diagnostics)

            let output = BufferedOutputByteStream()
            SwiftPackageCommand.ShowDependencies.dumpDependenciesOf(
                graph: graph,
                rootPackage: graph.rootPackages[graph.rootPackages.startIndex],
                mode: .dot,
                on: output
            )
            let dotFormat = output.bytes.description

            var alreadyPutOut: Set<Substring> = []
            for line in dotFormat.split(whereSeparator: { $0.isNewline }) {
                if alreadyPutOut.contains(line) {
                    Issue.record("Same line was already put out: \(line)")
                }
                alreadyPutOut.insert(line)
            }

            #if os(Windows)
                let pathSep = "\\"
            #else
                let pathSep = "/"
            #endif
            let expectedLines: [Substring] = [
                "\"\(pathSep)PackageA\" [label=\"packagea\\n\(pathSep)PackageA\\nunspecified\"]",
                "\"\(pathSep)PackageB\" [label=\"packageb\\n\(pathSep)PackageB\\nunspecified\"]",
                "\"\(pathSep)PackageC\" [label=\"packagec\\n\(pathSep)PackageC\\nunspecified\"]",
                "\"\(pathSep)PackageD\" [label=\"packaged\\n\(pathSep)PackageD\\nunspecified\"]",
                "\"\(pathSep)PackageA\" -> \"\(pathSep)PackageB\"",
                "\"\(pathSep)PackageA\" -> \"\(pathSep)PackageC\"",
                "\"\(pathSep)PackageB\" -> \"\(pathSep)PackageC\"",
                "\"\(pathSep)PackageB\" -> \"\(pathSep)PackageD\"",
                "\"\(pathSep)PackageC\" -> \"\(pathSep)PackageD\"",
            ]
            for expectedLine in expectedLines {
                #expect(
                    alreadyPutOut.contains(expectedLine),
                    "Expected line is not found: \(expectedLine)"
                )
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func showDependencies_redirectJsonOutput(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let root = tmpPath.appending(components: "root")
                let dep = tmpPath.appending(components: "dep")

                // Create root package.
                let mainFilePath = root.appending(components: "Sources", "root", "main.swift")
                try fs.writeFileContents(mainFilePath, string: "")
                try fs.writeFileContents(
                    root.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version:4.2
                        import PackageDescription
                        let package = Package(
                            name: "root",
                            dependencies: [.package(url: "../dep", from: "1.0.0")],
                            targets: [.target(name: "root", dependencies: ["dep"])]
                        )
                        """
                )

                // Create dependency.
                try fs.writeFileContents(
                    dep.appending(components: "Sources", "dep", "lib.swift"),
                    string: ""
                )
                try fs.writeFileContents(
                    dep.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version:4.2
                        import PackageDescription
                        let package = Package(
                            name: "dep",
                            products: [.library(name: "dep", targets: ["dep"])],
                            targets: [.target(name: "dep")]
                        )
                        """
                )

                do {
                    let depGit = GitRepository(path: dep)
                    try depGit.create()
                    try depGit.stageEverything()
                    try depGit.commit()
                    try depGit.tag(name: "1.0.0")
                }

                let resultPath = root.appending("result.json")
                _ = try await execute(
                    ["show-dependencies", "--format", "json", "--output-path", resultPath.pathString],
                    packagePath: root,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                expectFileExists(at: resultPath)
                let jsonOutput: Data = try fs.readFileContents(resultPath)
                let json = try JSON(data: jsonOutput)

                #expect(json["name"]?.string == "root")
                #expect(json["dependencies"]?[0]?["name"]?.string == "dep")
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Init,
        ),
    )
    struct InitCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initEmpty(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                try fs.createDirectory(path)
                _ = try await execute(
                    ["init", "--type", "empty"],
                    packagePath: path,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                expectFileExists(at: path.appending("Package.swift"))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Init,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initExecutable(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                try fs.createDirectory(path)
                _ = try await execute(
                    ["init", "--type", "executable"],
                    packagePath: path,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                let manifest = path.appending("Package.swift")
                let contents: String = try localFileSystem.readFileContents(manifest)
                let version = InitPackage.newPackageToolsVersion
                let versionSpecifier = "\(version.major).\(version.minor)"
                #expect(
                    contents.hasPrefix(
                        "// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"
                    )
                )

                expectFileExists(at: manifest)
                #expect(
                    try fs.getDirectoryContents(path.appending("Sources").appending(("Foo"))) == ["Foo.swift"]
                )
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Init,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initLibrary(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                try fs.createDirectory(path)
                _ = try await execute(
                    ["init"],
                    packagePath: path,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                expectFileExists(at: path.appending("Package.swift"))
                #expect(
                    try fs.getDirectoryContents(path.appending("Sources").appending("Foo")) == ["Foo.swift"]
                )
                #expect(try fs.getDirectoryContents(path.appending("Tests")).sorted() == ["FooTests"])
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.Init,
                .Feature.PackageType.Executable,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func initCustomNameExecutable(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("Foo")
                try fs.createDirectory(path)
                _ = try await execute(
                    ["init", "--name", "CustomName", "--type", "executable"],
                    packagePath: path,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                let manifest = path.appending("Package.swift")
                let contents: String = try localFileSystem.readFileContents(manifest)
                let version = InitPackage.newPackageToolsVersion
                let versionSpecifier = "\(version.major).\(version.minor)"
                #expect(
                    contents.hasPrefix(
                        "// swift-tools-version:\(version < .v5_4 ? "" : " ")\(versionSpecifier)\n"
                    )
                )

                expectFileExists(at: manifest)
                #expect(
                    try fs.getDirectoryContents(path.appending("Sources").appending("CustomName")) == [
                        "CustomName.swift"
                    ]
                )
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.AddDependency,
        ),
    )
    struct AddDependencyCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddDifferentDependencyWithSameURLTwiceFails(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let url = "https://github.com/swiftlang/swift-syntax.git"
                let manifest = """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            dependencies: [
                                .package(url: "\(url)", exact: "601.0.1")
                            ],
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                    """

                try localFileSystem.writeFileContents(path.appending("Package.swift"), string: manifest)

                await expectThrowsCommandExecutionError(
                    try await execute(
                        ["add-dependency", url, "--revision", "58e9de4e7b79e67c72a46e164158e3542e570ab6"],
                        packagePath: path,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stderr.contains(
                            "error: unable to add dependency 'https://github.com/swiftlang/swift-syntax.git' because it already exists in the list of dependencies"
                        )
                    )
                }
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddSameDependencyURLTwiceHasNoEffect(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let url = "https://github.com/swiftlang/swift-syntax.git"
                let manifest = """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            dependencies: [
                                .package(url: "\(url)", exact: "601.0.1"),
                            ],
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                    """
                let expected =
                    #".package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "601.0.1"),"#

                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: url,
                    requirementArgs: ["--exact", "601.0.1"],
                    expectedManifestString: expected,
                    buildData: data,
                )

                try expectManifest(path) {
                    let components = $0.components(separatedBy: expected)
                    #expect(components.count == 2)
                }
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddSameDependencyPathTwiceHasNoEffect(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let depPath = "../foo"
                let manifest = """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            dependencies: [
                                .package(path: "\(depPath)")
                            ],
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                    """

                let expected = #".package(path: "../foo")"#
                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: depPath,
                    requirementArgs: ["--type", "path"],
                    expectedManifestString: expected,
                    buildData: data,
                )

                try expectManifest(path) {
                    let components = $0.components(separatedBy: expected)
                    #expect(components.count == 2)
                }
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddSameDependencyRegistryTwiceHasNoEffect(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let registryId = "foo"
                let manifest = """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            dependencies: [
                                .package(id: "\(registryId)")
                            ],
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                    """

                let expected = #".package(id: "foo", exact: "1.0.0")"#
                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: registryId,
                    requirementArgs: ["--type", "registry", "--exact", "1.0.0"],
                    expectedManifestString: expected,
                    buildData: data,
                )

                try expectManifest(path) {
                    let components = $0.components(separatedBy: expected)
                    #expect(components.count == 2)
                }
            }
        }

        struct PackageAddDependencyTestData {
            let url: String
            let requirementArgs: CLIArguments
            let expectedManifestString: String
        }
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                PackageAddDependencyTestData(
                    // Test adding with --exact using the new helper
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--exact", "1.0.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "1.0.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --exact using the new helper
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--exact", "1.0.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "1.0.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --branch
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--branch", "main"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", branch: "main"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --revision
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--revision", "58e9de4e7b79e67c72a46e164158e3542e570ab6"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --from
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--from", "1.0.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", from: "1.0.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --from and --to
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--from", "2.0.0", "--to", "2.2.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", "2.0.0" ..< "2.2.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --up-to-next-minor-from
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--up-to-next-minor-from", "1.0.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", "1.0.0" ..< "1.1.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --up-to-next-minor-from and --to
                    url: "https://github.com/swiftlang/swift-syntax.git",
                    requirementArgs: ["--up-to-next-minor-from", "3.0.0", "--to", "3.3.0"],
                    expectedManifestString:
                        #".package(url: "https://github.com/swiftlang/swift-syntax.git", "3.0.0" ..< "3.3.0"),"#,
                ),
            ],
        )
        func packageAddURLDependency(
            buildData: BuildData,
            testData: PackageAddDependencyTestData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let manifest = """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                    """

                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: testData.url,
                    requirementArgs: testData.requirementArgs,
                    expectedManifestString: testData.expectedManifestString,
                    buildData: buildData,
                )
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                PackageAddDependencyTestData(
                    // Add absolute path dependency
                    url: "/absolute",
                    requirementArgs: ["--type", "path"],
                    expectedManifestString: #".package(path: "/absolute"),"#,
                ),
                PackageAddDependencyTestData(
                    // Add relative path dependency (operates on the modified manifest)
                    url: "../relative",
                    requirementArgs: ["--type", "path"],
                    expectedManifestString: #".package(path: "../relative"),"#,
                ),
            ],
        )
        func packageAddPathDependency(
            buildData: BuildData,
            testData: PackageAddDependencyTestData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)
                let manifest = """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(
                        name: "client",
                        targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                    )
                    """

                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: testData.url,
                    requirementArgs: testData.requirementArgs,
                    expectedManifestString: testData.expectedManifestString,
                    buildData: buildData,
                )
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                PackageAddDependencyTestData(
                    // Test adding with --exact
                    url: "scope.name",
                    requirementArgs: ["--type", "registry", "--exact", "1.0.0"],
                    expectedManifestString: #".package(id: "scope.name", exact: "1.0.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --from
                    url: "scope.name",
                    requirementArgs: ["--type", "registry", "--from", "1.0.0"],
                    expectedManifestString: #".package(id: "scope.name", from: "1.0.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --from and --to
                    url: "scope.name",
                    requirementArgs: ["--type", "registry", "--from", "2.0.0", "--to", "2.2.0"],
                    expectedManifestString: #".package(id: "scope.name", "2.0.0" ..< "2.2.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --up-to-next-minor-from
                    url: "scope.name",
                    requirementArgs: ["--type", "registry", "--up-to-next-minor-from", "1.0.0"],
                    expectedManifestString: #".package(id: "scope.name", "1.0.0" ..< "1.1.0"),"#,
                ),
                PackageAddDependencyTestData(
                    // Test adding with --up-to-next-minor-from and --to
                    url: "scope.name",
                    requirementArgs: [
                        "--type", "registry", "--up-to-next-minor-from", "3.0.0", "--to", "3.3.0",
                    ],
                    expectedManifestString: #".package(id: "scope.name", "3.0.0" ..< "3.3.0"),"#,
                ),
            ],
        )
        func packageAddRegistryDependency(
            buildData: BuildData,
            testData: PackageAddDependencyTestData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                let manifest = """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(
                        name: "client",
                        targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                    )
                    """
                try await executeAddURLDependencyAndAssert(
                    packagePath: path,
                    initialManifest: manifest,
                    url: testData.url,
                    requirementArgs: testData.requirementArgs,
                    expectedManifestString: testData.expectedManifestString,
                    buildData: buildData,
                )
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.AddTarget,
        ),
    )
    struct AddTargetCommandTests {
        @Test(
            .tags(
                .Feature.TargetType.Executable,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddTarget(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending("PackageB")
                try fs.createDirectory(path)

                try fs.writeFileContents(
                    path.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "client"
                        )
                        """
                )

                let manifest = path.appending("Package.swift")
                expectFileExists(at: manifest)

                // executable
                do {
                    _ = try await execute(
                      ["add-target", "client", "--dependencies", "MyLib", "OtherLib", "--type", "executable"],
                      packagePath: path,
                      configuration: data.config,
                      buildSystem: data.buildSystem,
                    )

                    let contents: String = try fs.readFileContents(manifest)

                    #expect(contents.contains(#"targets:"#))
                    #expect(contents.contains(#".executableTarget"#))
                    #expect(contents.contains(#"name: "client""#))
                    #expect(contents.contains(#"dependencies:"#))
                    #expect(contents.contains(#""MyLib""#))
                    #expect(contents.contains(#""OtherLib""#))
                }

                // library
                do {
                    _ = try await execute(
                      ["add-target", "MyLib", "--type", "library"],
                      packagePath: path,
                      configuration: data.config,
                      buildSystem: data.buildSystem,
                    )

                    let contents: String = try fs.readFileContents(manifest)

                    #expect(contents.contains(#"targets:"#))
                    #expect(contents.contains(#".target"#))
                    #expect(contents.contains(#"name: "MyLib""#))

                    expectFileExists(at: path.appending(components: ["Sources", "MyLib", "MyLib.swift"]))
                }

                // test
                do {
                    _ = try await execute(
                      ["add-target", "MyTest", "--type", "test"],
                      packagePath: path,
                      configuration: data.config,
                      buildSystem: data.buildSystem,
                    )

                    let contents: String = try fs.readFileContents(manifest)

                    #expect(contents.contains(#"targets:"#))
                    #expect(contents.contains(#".test"#))
                    #expect(contents.contains(#"name: "MyTest""#))

                    expectFileExists(at: path.appending(components: ["Tests", "MyTest", "MyTest.swift"]))
                }

                // macro + swift-syntax dependency
                do {
                    _ = try await execute(
                      ["add-target", "MyMacro", "--type", "macro"],
                      packagePath: path,
                      configuration: data.config,
                      buildSystem: data.buildSystem,
                    )

                    let contents: String = try fs.readFileContents(manifest)

                    #expect(contents.contains(#"dependencies:"#))
                    #expect(contents.contains(#".package(url: "https://github.com/swiftlang/swift-syntax.git"#))
                    #expect(contents.contains(#"targets:"#))
                    #expect(contents.contains(#".macro"#))
                    #expect(contents.contains(#"name: "MyMacro""#))
                    #expect(contents.contains(#"dependencies:"#))
                    #expect(contents.contains(#""SwiftCompilerPlugin""#))
                    #expect(contents.contains(#""SwiftSyntaxMacros""#))

                    expectFileExists(at: path.appending(components: ["Sources", "MyMacro", "MyMacro.swift"]))
                    expectFileExists(at: path.appending(components: ["Sources", "MyMacro", "ProvidedMacros.swift"]))
                }
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func packageAddTargetWithoutModuleSourcesFolder(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let manifest = tmpPath.appending("Package.swift")
                try fs.writeFileContents(
                    manifest,
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "SimpleExecutable",
                            targets: [
                                .executableTarget(name: "SimpleExecutable"),
                            ]
                        )
                        """
                )

                let sourcesFolder = tmpPath.appending("Sources")
                try fs.createDirectory(sourcesFolder)

                try fs.writeFileContents(
                    sourcesFolder.appending("main.swift"),
                    string:
                        """
                        print("Hello World")
                        """
                )

                _ = try await execute(
                    ["add-target", "client"],
                    packagePath: tmpPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                expectFileExists(at: manifest)
                let contents: String = try fs.readFileContents(manifest)

                #expect(contents.contains(#"targets:"#))
                #expect(contents.contains(#".executableTarget"#))
                #expect(contents.contains(#"name: "client""#))

                let fileStructure = try fs.getDirectoryContents(sourcesFolder)
                #expect(fileStructure.sorted() == ["SimpleExecutable", "client"])
                #expect(fs.isDirectory(sourcesFolder.appending("SimpleExecutable")))
                #expect(fs.isDirectory(sourcesFolder.appending("client")))
                #expect(
                    try fs.getDirectoryContents(sourcesFolder.appending("SimpleExecutable")) == ["main.swift"]
                )
                #expect(try fs.getDirectoryContents(sourcesFolder.appending("client")) == ["client.swift"])
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func addTargetWithoutManifestThrows(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                await expectThrowsCommandExecutionError(
                    try await execute(
                        ["add-target", "client"],
                        packagePath: tmpPath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stderr.contains(
                            "error: Could not find Package.swift in this directory or any of its parent directories."
                        )
                    )
                }
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.AddTargetDependency,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageAddTargetDependency(
        data: BuildData,
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("PackageB")
            try fs.createDirectory(path)

            try fs.writeFileContents(
                path.appending("Package.swift"),
                string:
                    """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(
                        name: "client",
                        targets: [ .target(name: "library") ]
                    )
                    """
            )
            try localFileSystem.writeFileContents(
                path.appending(components: "Sources", "library", "library.swift"),
                string:
                    """
                    public func Foo() { }
                    """
            )

            _ = try await execute(
                ["add-target-dependency", "--package", "other-package", "other-product", "library"],
                packagePath: path,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)
            let contents: String = try fs.readFileContents(manifest)

            #expect(contents.contains(#".product(name: "other-product", package: "other-package"#))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.AddProduct,
            .Feature.ProductType.StaticLibrary,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageAddProduct(
        data: BuildData,
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("PackageB")
            try fs.createDirectory(path)

            try fs.writeFileContents(
                path.appending("Package.swift"),
                string:
                    """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(
                        name: "client"
                    )
                    """
            )

            _ = try await execute(
                ["add-product", "MyLib", "--targets", "MyLib", "--type", "static-library"],
                packagePath: path,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)
            let contents: String = try fs.readFileContents(manifest)

            #expect(contents.contains(#"products:"#))
            #expect(contents.contains(#".library"#))
            #expect(contents.contains(#"name: "MyLib""#))
            #expect(contents.contains(#"type: .static"#))
            #expect(contents.contains(#"targets:"#))
            #expect(contents.contains(#""MyLib""#))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.AddSetting,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageAddSetting(
        data: BuildData,
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let fs = localFileSystem
            let path = tmpPath.appending("PackageA")
            try fs.createDirectory(path)

            try fs.writeFileContents(
                path.appending("Package.swift"),
                string:
                    """
                    // swift-tools-version: 6.2
                    import PackageDescription
                    let package = Package(
                        name: "A",
                        targets: [ .target(name: "test") ]
                    )
                    """
            )

            _ = try await execute(
                [
                    "add-setting",
                    "--target", "test",
                    "--swift", "languageMode=6",
                    "--swift", "upcomingFeature=ExistentialAny:migratable",
                    "--swift", "experimentalFeature=TrailingCommas",
                    "--swift", "StrictMemorySafety",
                ],
                packagePath: path,
                configuration: data.config,
                buildSystem: data.buildSystem,

            )

            let manifest = path.appending("Package.swift")
            expectFileExists(at: manifest)
            let contents: String = try fs.readFileContents(manifest)

            #expect(contents.contains(#"swiftSettings:"#))
            #expect(contents.contains(#".swiftLanguageMode(.v6)"#))
            #expect(contents.contains(#".enableUpcomingFeature("ExistentialAny:migratable")"#))
            #expect(contents.contains(#".enableExperimentalFeature("TrailingCommas")"#))
            #expect(contents.contains(#".strictMemorySafety()"#))
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8774", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8380", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8416", relationship: .defect),  // swift run linux issue with swift build,
        .tags(
            .Feature.Command.Package.Edit,
            .Feature.Command.Package.Unedit,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageEditAndUnedit(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/PackageEdit") { fixturePath in
            let fooPath = fixturePath.appending("foo")
            func build() async throws -> (stdout: String, stderr: String) {
                return try await executeSwiftBuild(
                    fooPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            }

            // Put bar and baz in edit mode.
            _ = try await execute(
                ["edit", "bar", "--branch", "bugfix"],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            _ = try await execute(
                ["edit", "baz", "--branch", "bugfix"],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            // Path to the executable.
            let binPath = try fooPath.appending(components: data.buildSystem.binPath(for: data.config))
            let exec = [
                binPath.appending("foo").pathString
            ]

            // We should see it now in packages directory.
            let editsPath = fooPath.appending(components: "Packages", "bar")
            expectDirectoryExists(at: editsPath)

            let bazEditsPath = fooPath.appending(components: "Packages", "baz")
            expectDirectoryExists(at: bazEditsPath)
            // Removing baz externally should just emit an warning and not a build failure.
            try localFileSystem.removeFileTree(bazEditsPath)

            // Do a modification in bar and build.
            try localFileSystem.writeFileContents(
                editsPath.appending(components: "Sources", "bar.swift"),
                bytes: "public let theValue = 88888\n"
            )
            let (_, stderr) = try await build()

            #expect(
                stderr.contains(
                    "dependency 'baz' was being edited but is missing; falling back to original checkout"
                )
            )
            // We should be able to see that modification now.
            let processValue = try await AsyncProcess.checkNonZeroExit(arguments: exec)
            #expect(processValue == "88888\(ProcessInfo.EOL)")

            // The branch of edited package should be the one we provided when putting it in edit mode.
            let editsRepo = GitRepository(path: editsPath)
            #expect(try editsRepo.currentBranch() == "bugfix")

            // It shouldn't be possible to unedit right now because of uncommitted changes.
            do {
                _ = try await execute(
                    ["unedit", "bar"],
                    packagePath: fooPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                Issue.record("Unexpected unedit success")
            } catch {}

            try editsRepo.stageEverything()
            try editsRepo.commit()

            // It shouldn't be possible to unedit right now because of unpushed changes.
            do {
                _ = try await execute(
                    ["unedit", "bar"],
                    packagePath: fooPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                Issue.record("Unexpected unedit success")
            } catch {}

            // Push the changes.
            try editsRepo.push(remote: "origin", branch: "bugfix")

            // We should be able to unedit now.
            _ = try await execute(
                ["unedit", "bar"],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            // Test editing with a path i.e. ToT development.
            let bazTot = fixturePath.appending("tot")
            try await execute(
                ["edit", "baz", "--path", bazTot.pathString],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(localFileSystem.exists(bazTot))
            #expect(localFileSystem.isSymlink(bazEditsPath))

            // Edit a file in baz ToT checkout.
            let bazTotPackageFile = bazTot.appending("Package.swift")
            var content: String = try localFileSystem.readFileContents(bazTotPackageFile)
            content += "\n// Edited."
            try localFileSystem.writeFileContents(bazTotPackageFile, string: content)

            // Unediting baz will remove the symlink but not the checked out package.
            try await execute(
                ["unedit", "baz"],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(localFileSystem.exists(bazTot))
            #expect(!localFileSystem.isSymlink(bazEditsPath))

            // Check that on re-editing with path, we don't make a new clone.
            try await execute(
                ["edit", "baz", "--path", bazTot.pathString],
                packagePath: fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(localFileSystem.isSymlink(bazEditsPath))
            #expect(try localFileSystem.readFileContents(bazTotPackageFile) == content)
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8774", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8380", relationship: .defect),
        .tags(
            .Feature.Command.Package.Clean,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageClean(
        data: BuildData,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")

            // Build it.
            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            let buildPath = packageRoot.appending(".build")
            let binPath = try buildPath.appending(components: data.buildSystem.binPath(for: data.config, scratchPath: []))
            let binFile = binPath.appending(executableName("Bar"))
            expectFileExists(at: binFile)
            #expect(localFileSystem.isDirectory(buildPath))

            // Clean, and check for removal of the build directory but not Packages.
            _ = try await execute(
                ["clean"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            expectFileDoesNotExists(at: binFile)
            // Clean again to ensure we get no error.
            _ = try await execute(
                ["clean"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8774", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8380", relationship: .defect),
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Package.Reset,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageReset(
        data: BuildData,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")

            // Build it.
            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem
            )
            let buildPath = packageRoot.appending(".build")
            let binPath = try buildPath.appending(components: data.buildSystem.binPath(for: data.config, scratchPath: [], ))
            let binFile = binPath.appending(executableName("Bar"))
            expectFileExists(at: binFile)
            #expect(localFileSystem.isDirectory(buildPath))
            // Clean, and check for removal of the build directory but not Packages.

            _ = try await execute(
                ["clean"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            expectFileDoesNotExists(at: binFile)
            try #expect(
                !localFileSystem.getDirectoryContents(buildPath.appending("repositories")).isEmpty
            )

            // Fully clean.
            _ = try await execute(
                ["reset"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            #expect(!localFileSystem.isDirectory(buildPath))

            // Test that we can successfully run reset again.
            _ = try await execute(
                ["reset"],
                packagePath: packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        }
    }

    @Test(
        .tags(.Feature.Command.Package.PurgeCache),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func purgeCacheWithoutPackage(
        data: BuildData,
    ) async throws {
        try await withKnownIssue(
            isIntermittent: ProcessInfo.isHostAmazonLinux2() //rdar://134238535
        ) {
            // Create a temporary directory without Package.swift
            try await fixture(name: "Miscellaneous") { fixturePath in
                let tempDir = fixturePath.appending("empty-dir-for-purge-test")
                try localFileSystem.createDirectory(tempDir, recursive: true)

                // Use a unique temporary cache directory to avoid conflicts with parallel tests
                try await withTemporaryDirectory(removeTreeOnDeinit: true) { cacheDir in
                    let result = try await executeSwiftPackage(
                        tempDir,
                        configuration: data.config,
                        extraArgs: ["purge-cache", "--cache-path", cacheDir.pathString],
                        buildSystem: data.buildSystem
                    )

                    #expect(!result.stderr.contains("Could not find Package.swift"))
                }
            }
        } when: {
            ProcessInfo.isHostAmazonLinux2()
        }
    }

    @Test(
        .tags(.Feature.Command.Package.PurgeCache),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func purgeCacheInPackageDirectory(
        data: BuildData,
    ) async throws {
        // Test that purge-cache works in a package directory and successfully purges caches
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")

            // Use a unique temporary cache directory for this test
            try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
                let cacheDir = tempDir.appending("test-cache")
                let cacheArgs = ["--cache-path", cacheDir.pathString]

                // Resolve dependencies to populate cache
                // Note: This fixture uses local dependencies, so only manifest cache will be populated
                try await executeSwiftPackage(
                    packageRoot,
                    configuration: data.config,
                    extraArgs: ["resolve"] + cacheArgs,
                    buildSystem: data.buildSystem
                )

                // Verify manifest cache was populated
                let manifestsCache = cacheDir.appending(components: "manifests")
                expectDirectoryExists(at: manifestsCache)

                // Check for manifest.db file (main database file)
                let manifestDB = manifestsCache.appending("manifest.db")
                let hasManifestDB = localFileSystem.exists(manifestDB)

                // Check for SQLite auxiliary files that might exist
                let manifestDBWAL = manifestsCache.appending("manifest.db-wal")
                let manifestDBSHM = manifestsCache.appending("manifest.db-shm")
                let hasAuxFiles = localFileSystem.exists(manifestDBWAL) || localFileSystem.exists(manifestDBSHM)

                // At least one manifest database file should exist
                #expect(hasManifestDB || hasAuxFiles, "Manifest cache should be populated after resolve")

                // Run purge-cache
                let result = try await executeSwiftPackage(
                    packageRoot,
                    configuration: data.config,
                    extraArgs: ["purge-cache"] + cacheArgs,
                    buildSystem: data.buildSystem
                )

                // Verify command succeeded
                #expect(!result.stderr.contains("Could not find Package.swift"))

                // Verify manifest.db was removed (the purge implementation removes this file)
                expectFileDoesNotExists(at: manifestDB, "manifest.db should be removed after purge")

                // Note: SQLite auxiliary files (WAL/SHM) may or may not be removed depending on SQLite state
                // The important check is that the main database file is removed
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func resolvingBranchAndRevision(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/PackageEdit") { fixturePath in
            let fooPath = fixturePath.appending("foo")

            @discardableResult
            func localExecute(_ args: String..., printError: Bool = true) async throws -> String {
                return try await execute(
                    [] + args,
                    packagePath: fooPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                ).stdout
            }

            try await localExecute("update")

            let packageResolvedFile = fooPath.appending("Package.resolved")
            expectFileExists(at: packageResolvedFile)

            // Update bar repo.
            let barPath = fixturePath.appending("bar")
            let barRepo = GitRepository(path: barPath)
            try barRepo.checkout(newBranch: "YOLO")
            let yoloRevision = try barRepo.getCurrentRevision()

            // Try to resolve `bar` at a branch.
            do {
                try await localExecute("resolve", "bar", "--branch", "YOLO")
                let resolvedPackagesStore = try ResolvedPackagesStore(
                    packageResolvedFile: packageResolvedFile,
                    workingDirectory: fixturePath,
                    fileSystem: localFileSystem,
                    mirrors: .init()
                )
                let state = ResolvedPackagesStore.ResolutionState.branch(
                    name: "YOLO",
                    revision: yoloRevision.identifier
                )
                let identity = PackageIdentity(path: barPath)
                #expect(resolvedPackagesStore.resolvedPackages[identity]?.state == state)
            }

            // Try to resolve `bar` at a revision.
            do {
                try await localExecute("resolve", "bar", "--revision", yoloRevision.identifier)
                let resolvedPackagesStore = try ResolvedPackagesStore(
                    packageResolvedFile: packageResolvedFile,
                    workingDirectory: fixturePath,
                    fileSystem: localFileSystem,
                    mirrors: .init()
                )
                let state = ResolvedPackagesStore.ResolutionState.revision(yoloRevision.identifier)
                let identity = PackageIdentity(path: barPath)
                #expect(resolvedPackagesStore.resolvedPackages[identity]?.state == state)
            }

            // Try to resolve `bar` at a bad revision.
            await #expect(throws: (any Error).self) {
                try await localExecute("resolve", "bar", "--revision", "xxxxx")
            }
        }
    }

    @Test(
        // windows long path issue
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8774", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8380", relationship: .defect),
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Package.Resolve,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageResolved(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/PackageEdit") { fixturePath in
            let fooPath = fixturePath.appending("foo")
            let binPath = try fooPath.appending(components: data.buildSystem.binPath(for: data.config))
            let exec = [
                binPath.appending("foo").pathString
            ]

            // Build and check.
            _ = try await executeSwiftBuild(
                fooPath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            let value = try await AsyncProcess.checkNonZeroExit(arguments: exec).spm_chomp()
            #expect(value == "\(5)")


            // Get path to `bar` checkout.
            let barPath = try SwiftPM.packagePath(for: "bar", packageRoot: fooPath)

            // Checks the content of checked out `bar.swift`.
            func checkBar(_ value: Int, sourceLocation: SourceLocation = #_sourceLocation) throws {
                let contents: String = try localFileSystem.readFileContents(
                    barPath.appending(components: "Sources", "bar.swift")
                )
                #expect(
                    contents.spm_chomp().hasSuffix("\(value)"),
                    "got \(contents)",
                    sourceLocation: sourceLocation
                )
            }

            // We should see a `Package.resolved` file now.
            let packageResolvedFile = fooPath.appending("Package.resolved")
            expectFileExists(at: packageResolvedFile)

            // Test `Package.resolved` file.
            do {
                let resolvedPackagesStore = try ResolvedPackagesStore(
                    packageResolvedFile: packageResolvedFile,
                    workingDirectory: fixturePath,
                    fileSystem: localFileSystem,
                    mirrors: .init()
                )
                #expect(resolvedPackagesStore.resolvedPackages.count == 2)
                for pkg in ["bar", "baz"] {
                    let path = try SwiftPM.packagePath(for: pkg, packageRoot: fooPath)
                    let resolvedPackage = resolvedPackagesStore.resolvedPackages[
                        PackageIdentity(path: path)
                    ]!
                    #expect(resolvedPackage.packageRef.identity == PackageIdentity(path: path))
                    guard case .localSourceControl(let path) = resolvedPackage.packageRef.kind,
                          path.pathString.hasSuffix(pkg)
                    else {
                        Issue.record("invalid resolved package location \(path)")
                        return
                    }
                    switch resolvedPackage.state {
                    case .version(let version, revision: _):
                        #expect(version == "1.2.3")
                    default:
                        Issue.record("invalid `Package.resolved` state")
                    }
                }
            }

            @discardableResult
            func localExecute(_ args: String...) async throws -> String {
                return try await execute(
                    [] + args,
                    packagePath: fooPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                ).stdout
            }

            // Try to pin bar.
            do {
                try await localExecute("resolve", "bar")
                let resolvedPackagesStore = try ResolvedPackagesStore(
                    packageResolvedFile: packageResolvedFile,
                    workingDirectory: fixturePath,
                    fileSystem: localFileSystem,
                    mirrors: .init()
                )
                let identity = PackageIdentity(path: barPath)
                // let resolvedPackageIdentify = try #require(resolvedPackagesStore.resolvedPackages[identity])
                // switch resolvedPackageIdentify.state {
                switch resolvedPackagesStore.resolvedPackages[identity]?.state {
                case .version(let version, revision: _):
                    #expect(version == "1.2.3")
                default:
                    Issue.record("invalid resolved package state")
                }
            }

            // Update bar repo.
            do {
                let barPath = fixturePath.appending("bar")
                let barRepo = GitRepository(path: barPath)
                try localFileSystem.writeFileContents(
                    barPath.appending(components: "Sources", "bar.swift"),
                    bytes: "public let theValue = 6\n"
                )
                try barRepo.stageEverything()
                try barRepo.commit()
                try barRepo.tag(name: "1.2.4")
            }

            // Running `package update` should update the package.
            do {
                try await localExecute("update")
                try checkBar(6)
            }

            // We should be able to revert to a older version.
            do {
                try await localExecute("resolve", "bar", "--version", "1.2.3")
                let resolvedPackagesStore = try ResolvedPackagesStore(
                    packageResolvedFile: packageResolvedFile,
                    workingDirectory: fixturePath,
                    fileSystem: localFileSystem,
                    mirrors: .init()
                )
                let identity = PackageIdentity(path: barPath)
                switch resolvedPackagesStore.resolvedPackages[identity]?.state {
                case .version(let version, revision: _):
                    #expect(version == "1.2.3")
                default:
                    Issue.record("invalid resolved package state")
                }
                try checkBar(5)
            }

            // Try resolving a dependency which is in edit mode.
            do {
                try await localExecute("edit", "bar", "--branch", "bugfix")
                await expectThrowsCommandExecutionError(try await localExecute("resolve", "bar")) {
                    error in
                    #expect(error.stderr.contains("error: edited dependency 'bar' can't be resolved"))
                }
                try await localExecute("unedit", "bar")
            }
        }
    }

    @Test(
        .issue(
            "error: Package.resolved file is corrupted or malformed, needs investigation",
            relationship: .defect
        ),
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func onlyUseVersionsFromResolvedFileFetchesWithExistingState(
        data: BuildData,
    ) async throws {
        // try XCTSkipOnWindows(because: "error: Package.resolved file is corrupted or malformed, needs investigation")
        func writeResolvedFile(
            packageDir: AbsolutePath,
            repositoryURL: String,
            revision: String,
            version: String
        ) throws {
            try localFileSystem.writeFileContents(
                packageDir.appending("Package.resolved"),
                string:
                    """
                    {
                      "object": {
                        "pins": [
                          {
                            "package": "library",
                            "repositoryURL": "\(repositoryURL)",
                            "state": {
                              "branch": null,
                              "revision": "\(revision)",
                              "version": "\(version)"
                            }
                          }
                        ]
                      },
                      "version": 1
                    }
                    """
            )
        }
        try await withKnownIssue {
            try await testWithTemporaryDirectory { tmpPath in
                let packageDir = tmpPath.appending(components: "library")
                try localFileSystem.writeFileContents(
                    packageDir.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version:5.0
                        import PackageDescription
                        let package = Package(
                            name: "library",
                            products: [ .library(name: "library", targets: ["library"]) ],
                            targets: [ .target(name: "library") ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "library", "library.swift"),
                    string:
                        """
                        public func Foo() { }
                        """
                )

                let depGit = GitRepository(path: packageDir)
                try depGit.create()
                try depGit.stageEverything()
                try depGit.commit()
                try depGit.tag(name: "1.0.0")

                let initialRevision = try depGit.revision(forTag: "1.0.0")
                let repositoryURL = #"file://\#(packageDir.pathString)"#

                let clientDir = tmpPath.appending(components: "client")
                try localFileSystem.writeFileContents(
                    clientDir.appending("Package.swift"),
                    string:
                        #"""
                        // swift-tools-version:5.0
                        import PackageDescription
                        let package = Package(
                            name: "client",
                            dependencies: [ .package(url: "\#(repositoryURL)", from: "1.0.0") ],
                            targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                        )
                        """#
                )
                try localFileSystem.writeFileContents(
                    clientDir.appending(components: "Sources", "client", "main.swift"),
                    string:
                        """
                        print("hello")
                        """
                )

                // Initial resolution with clean state.
                do {
                    try writeResolvedFile(
                        packageDir: clientDir,
                        repositoryURL: repositoryURL,
                        revision: initialRevision,
                        version: "1.0.0"
                    )
                    let (_, err) = try await execute(
                        ["resolve", "--only-use-versions-from-resolved-file"],
                        packagePath: clientDir,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(err.contains("Fetching \(repositoryURL)"))
                }

                // Make a change to the dependency and tag a new version.
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "library", "library.swift"),
                    string:
                        """
                        public func Best() { }
                        """
                )
                try depGit.stageEverything()
                try depGit.commit()
                try depGit.tag(name: "1.0.1")
                let updatedRevision = try depGit.revision(forTag: "1.0.1")

                // Require new version but re-use existing state that hasn't fetched the latest revision, yet.
                do {
                    try writeResolvedFile(
                        packageDir: clientDir,
                        repositoryURL: repositoryURL,
                        revision: updatedRevision,
                        version: "1.0.1"
                    )
                    let (_, err) = try await execute(
                        ["resolve", "--only-use-versions-from-resolved-file"],
                        packagePath: clientDir,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(!err.contains("Fetching \(repositoryURL)"))
                    #expect(err.contains("Updating \(repositoryURL)"))

                }

                // And again
                do {
                    let (_, err) = try await execute(
                        ["resolve", "--only-use-versions-from-resolved-file"],
                        packagePath: clientDir,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(!err.contains("Updating \(repositoryURL)"))
                    #expect(!err.contains("Fetching \(repositoryURL)"))
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Package.Resolve,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func symlinkedDependency(
        data: BuildData,
    ) async throws {
        try await testWithTemporaryDirectory { path in
            let fs = localFileSystem
            let root = path.appending(components: "root")
            let dep = path.appending(components: "dep")
            let depSym = path.appending(components: "depSym")

            // Create root package.
            try fs.writeFileContents(
                root.appending(components: "Sources", "root", "main.swift"),
                string: ""
            )
            try fs.writeFileContents(
                root.appending("Package.swift"),
                string:
                    """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "root",
                        dependencies: [.package(url: "../depSym", from: "1.0.0")],
                        targets: [.target(name: "root", dependencies: ["dep"])]
                    )

                    """
            )

            // Create dependency.
            try fs.writeFileContents(dep.appending(components: "Sources", "dep", "lib.swift"), string: "")
            try fs.writeFileContents(
                dep.appending("Package.swift"),
                string:
                    """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "dep",
                        products: [.library(name: "dep", targets: ["dep"])],
                        targets: [.target(name: "dep")]
                    )
                    """
            )
            do {
                let depGit = GitRepository(path: dep)
                try depGit.create()
                try depGit.stageEverything()
                try depGit.commit()
                try depGit.tag(name: "1.0.0")
            }

            // Create symlink to the dependency.
            try fs.createSymbolicLink(depSym, pointingAt: dep, relative: false)

            _ = try await execute(
                ["resolve"],
                packagePath: root,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Config,
        ),
    )
    struct ConfigCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func mirrorConfigDeprecation(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { fixturePath in
                localFileSystem.createEmptyFiles(
                    at: fixturePath,
                    files:
                        "/Sources/Foo/Foo.swift",
                    "/Package.swift"
                )

                let (_, stderr) = try await execute(
                    [
                        "config", "set-mirror", "--package-url", "https://github.com/foo/bar", "--mirror-url",
                        "https://mygithub.com/foo/bar",
                    ],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(
                    stderr.contains("warning: '--package-url' option is deprecated; use '--original' instead")
                )
                #expect(
                    stderr.contains("warning: '--mirror-url' option is deprecated; use '--mirror' instead")
                )
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func mirrorConfig(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { fixturePath in
                let fs = localFileSystem
                let packageRoot = fixturePath.appending("Foo")
                let configOverride = fixturePath.appending("configoverride")
                let configFile = Workspace.DefaultLocations.mirrorsConfigurationFile(
                    forRootPackage: packageRoot
                )

                fs.createEmptyFiles(
                    at: packageRoot,
                    files:
                        "/Sources/Foo/Foo.swift",
                    "/Tests/FooTests/FooTests.swift",
                    "/Package.swift",
                    "anchor"
                )

                // Test writing.
                try await execute(
                    [
                        "config", "set-mirror", "--original", "https://github.com/foo/bar", "--mirror",
                        "https://mygithub.com/foo/bar",
                    ],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                try await execute(
                    [
                        "config", "set-mirror", "--original",
                        "git@github.com:swiftlang/swift-package-manager.git", "--mirror",
                        "git@mygithub.com:foo/swift-package-manager.git",
                    ],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(fs.isFile(configFile))

                // Test env override.
                try await execute(
                    [
                        "config", "set-mirror", "--original", "https://github.com/foo/bar", "--mirror",
                        "https://mygithub.com/foo/bar",
                    ],
                    packagePath: packageRoot,
                    env: ["SWIFTPM_MIRROR_CONFIG": configOverride.pathString],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(fs.isFile(configOverride))
                let content: String = try fs.readFileContents(configOverride)
                #expect(content.contains("mygithub"))

                // Test reading.
                var (stdout, _) = try await execute(
                    ["config", "get-mirror", "--original", "https://github.com/foo/bar"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.spm_chomp() == "https://mygithub.com/foo/bar")
                (stdout, _) = try await execute(
                    [
                        "config", "get-mirror", "--original",
                        "git@github.com:swiftlang/swift-package-manager.git",
                    ],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.spm_chomp() == "git@mygithub.com:foo/swift-package-manager.git")

                func check(stderr: String, _ block: () async throws -> Void) async {
                    await expectThrowsCommandExecutionError(try await block()) { error in
                        #expect(error.stderr.contains(stderr))
                    }
                }

                await check(stderr: "not found\n") {
                    try await execute(
                        ["config", "get-mirror", "--original", "foo"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                }

                // Test deletion.
                try await execute(
                    ["config", "unset-mirror", "--original", "https://github.com/foo/bar"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                try await execute(
                    [
                        "config", "unset-mirror", "--original",
                        "git@mygithub.com:foo/swift-package-manager.git",
                    ],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                await check(stderr: "not found\n") {
                    try await execute(
                        ["config", "get-mirror", "--original", "https://github.com/foo/bar"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                }
                await check(stderr: "not found\n") {
                    try await execute(
                        [
                            "config", "get-mirror", "--original",
                            "git@github.com:swiftlang/swift-package-manager.git",
                        ],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                }

                await check(stderr: "error: Mirror not found for 'foo'\n") {
                    try await execute(
                        ["config", "unset-mirror", "--original", "foo"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                }
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.DumpPackage,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func mirrorSimple(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { fixturePath in
                let fs = localFileSystem
                let packageRoot = fixturePath.appending("MyPackage")
                let configFile = Workspace.DefaultLocations.mirrorsConfigurationFile(
                    forRootPackage: packageRoot
                )

                fs.createEmptyFiles(
                    at: packageRoot,
                    files:
                        "/Sources/Foo/Foo.swift",
                    "/Tests/FooTests/FooTests.swift",
                    "/Package.swift"
                )

                try fs.writeFileContents(
                    packageRoot.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.7
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            dependencies: [
                                .package(url: "https://scm.com/org/foo", from: "1.0.0")
                            ],
                            targets: [
                                .executableTarget(
                                    name: "MyTarget",
                                    dependencies: [
                                        .product(name: "Foo", package: "foo")
                                    ])
                            ]
                        )
                        """
                )

                try await execute(
                    [
                        "config", "set-mirror", "--original", "https://scm.com/org/foo", "--mirror",
                        "https://scm.com/org/bar",
                    ],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(fs.isFile(configFile))

                let (stdout, _) = try await execute(
                    ["dump-package"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("https://scm.com/org/bar"))
                #expect(!stdout.contains("https://scm.com/org/foo"))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.DumpPackage,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func mirrorURLToRegistry(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { fixturePath in
                let fs = localFileSystem
                let packageRoot = fixturePath.appending("MyPackage")
                let configFile = Workspace.DefaultLocations.mirrorsConfigurationFile(
                    forRootPackage: packageRoot
                )

                fs.createEmptyFiles(
                    at: packageRoot,
                    files:
                        "/Sources/Foo/Foo.swift",
                    "/Tests/FooTests/FooTests.swift",
                    "/Package.swift"
                )

                try fs.writeFileContents(
                    packageRoot.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.7
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            dependencies: [
                                .package(url: "https://scm.com/org/foo", from: "1.0.0")
                            ],
                            targets: [
                                .executableTarget(
                                    name: "MyTarget",
                                    dependencies: [
                                        .product(name: "Foo", package: "foo")
                                    ])
                            ]
                        )
                        """
                )

                try await execute(
                    ["config", "set-mirror", "--original", "https://scm.com/org/foo", "--mirror", "org.bar"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(fs.isFile(configFile))

                let (stdout, _) = try await execute(
                    ["dump-package"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("org.bar"))
                #expect(!stdout.contains("https://scm.com/org/foo"))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Package.DumpPackage,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func mirrorRegistryToURL(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { fixturePath in
                let fs = localFileSystem
                let packageRoot = fixturePath.appending("MyPackage")
                let configFile = Workspace.DefaultLocations.mirrorsConfigurationFile(
                    forRootPackage: packageRoot
                )

                fs.createEmptyFiles(
                    at: packageRoot,
                    files:
                        "/Sources/Foo/Foo.swift",
                    "/Tests/FooTests/FooTests.swift",
                    "/Package.swift"
                )

                try fs.writeFileContents(
                    packageRoot.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.7
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            dependencies: [
                                .package(id: "org.foo", from: "1.0.0")
                            ],
                            targets: [
                                .executableTarget(
                                    name: "MyTarget",
                                    dependencies: [
                                        .product(name: "Foo", package: "org.foo")
                                    ])
                            ]
                        )
                        """
                )

                try await execute(
                    ["config", "set-mirror", "--original", "org.foo", "--mirror", "https://scm.com/org/bar"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(fs.isFile(configFile))

                let (stdout, _) = try await execute(
                    ["dump-package"],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("https://scm.com/org/bar"))
                #expect(!stdout.contains("org.foo"))
            }
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageLoadingCommandPathResilience(
        data: BuildData,
    ) async throws {
        try await fixture(name: "ValidLayouts/SingleModule") { fixturePath in
            try await testWithTemporaryDirectory { tmpdir in
                // Create fake `xcrun` and `sandbox-exec` commands.
                let fakeBinDir = tmpdir
                for fakeCmdName in ["xcrun", "sandbox-exec"] {
                    let fakeCmdPath = fakeBinDir.appending(component: fakeCmdName)
                    try localFileSystem.writeFileContents(
                        fakeCmdPath,
                        string:
                            """
                            #!/bin/sh
                            echo "wrong \(fakeCmdName) invoked"
                            exit 1
                            """
                    )
                    try localFileSystem.chmod(.executable, path: fakeCmdPath)
                }

                // Invoke `swift-package`, passing in the overriding `PATH` environment variable.
                let packageRoot = fixturePath.appending("Library")
                let patchedPATH = fakeBinDir.pathString + ":" + ProcessInfo.processInfo.environment["PATH"]!
                let (stdout, _) = try await execute(
                    ["dump-package"],
                    packagePath: packageRoot,
                    env: ["PATH": patchedPATH],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )

                // Check that the wrong tools weren't invoked.  We can't just check the exit code because of fallbacks.
                #expect(!stdout.contains("wrong xcrun invoked"))
                #expect(!stdout.contains("wrong sandbox-exec invoked"))
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.Migrate,
        ),
    )
    struct MigrateCommandTests {
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandHelp(
            data: BuildData,
        ) async throws {
            let (stdout, _) = try await execute(
                ["migrate", "--help"],
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

            // Global options are hidden.
            #expect(!stdout.contains("--package-path"))
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandNoFeatures(
            data: BuildData,
        ) async throws {
            try await expectThrowsCommandExecutionError(
                await execute(
                    ["migrate"],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                #expect(
                    error.stderr.contains("error: Missing expected argument '--to-feature <to-feature>'")
                )
            }
        }

        @Test(
            .supportsSupportedFeatures,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandUnknownFeature(
            data: BuildData,
        ) async throws {
            try await expectThrowsCommandExecutionError(
                await execute(
                    ["migrate", "--to-feature", "X"],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                #expect(
                    error.stderr.contains("error: Unsupported feature 'X'. Available features:")
                )
            }
        }

        @Test(
            .supportsSupportedFeatures,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandNonMigratableFeature(
            data: BuildData,
        ) async throws {
            try await expectThrowsCommandExecutionError(
                await execute(
                    ["migrate", "--to-feature", "StrictConcurrency"],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                #expect(
                    error.stderr.contains("error: Feature 'StrictConcurrency' is not migratable")
                )
            }
        }

        struct MigrateCommandTestData {
            let featureName: String
            let expectedSummary: String
        }
        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            .IssueWindowsCannotSaveAttachment,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                // When updating these, make sure we keep testing both the singular and
                // plural forms of the nouns in the summary.
                MigrateCommandTestData(
                    featureName: "ExistentialAny",
                    expectedSummary: "Applied 5 fix-its in 1 file",
                ),
                MigrateCommandTestData(
                    featureName: "StrictMemorySafety",
                    expectedSummary: "Applied 1 fix-it in 1 file",
                ),
                MigrateCommandTestData(
                    featureName: "InferIsolatedConformances",
                    expectedSummary: "Applied 3 fix-its in 2 files",
                ),
            ],
        )
        func migrateCommand(
            buildData: BuildData,
            testData: MigrateCommandTestData,
        ) async throws {
            let featureName = testData.featureName
            let expectedSummary = testData.expectedSummary
            try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "SwiftMigrate/\(featureName)Migration") { fixturePath in
                let sourcePaths: [AbsolutePath]
                let fixedSourcePaths: [AbsolutePath]

                do {
                    let sourcesPath = fixturePath.appending(components: "Sources")
                    let fixedSourcesPath = sourcesPath.appending("Fixed")

                    sourcePaths = try localFileSystem.getDirectoryContents(sourcesPath).filter { filename in
                        filename.hasSuffix(".swift")
                    }.sorted().map { filename in
                        sourcesPath.appending(filename)
                    }
                    fixedSourcePaths = try localFileSystem.getDirectoryContents(fixedSourcesPath).filter {
                        filename in
                        filename.hasSuffix(".swift")
                    }.sorted().map { filename in
                        fixedSourcesPath.appending(filename)
                    }
                }

                let (stdout, _) = try await execute(
                    ["migrate", "--to-feature", featureName],
                    packagePath: fixturePath,
                    configuration: buildData.config,
                    buildSystem: buildData.buildSystem,

                )

                #expect(sourcePaths.count == fixedSourcePaths.count)

                for (sourcePath, fixedSourcePath) in zip(sourcePaths, fixedSourcePaths) {
                    let sourceContent = try localFileSystem.readFileContents(sourcePath)
                    let fixedSourceContent = try localFileSystem.readFileContents(fixedSourcePath)
                    #expect(sourceContent == fixedSourceContent)
                }

                let regexMatch = try Regex("> \(expectedSummary)" + #" \([0-9]\.[0-9]{1,3}s\)"#)
                #expect(stdout.contains(regexMatch))
            }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows && buildData.buildSystem == .swiftbuild
            }
        }

        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandWithBuildToolPlugins(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "SwiftMigrate/ExistentialAnyWithPluginMigration") { fixturePath in
                let (stdout, _) = try await execute(
                    ["migrate", "--to-feature", "ExistentialAny"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,

                )

                // Check the plugin target in the manifest wasn't updated
                let manifestContent = try localFileSystem.readFileContents(
                    fixturePath.appending(component: "Package.swift")
                ).description
                #expect(
                    manifestContent.contains(
                        ".plugin(name: \"Plugin\", capability: .buildTool, dependencies: [\"Tool\"]),"
                    )
                )

                // Building the package produces migration fix-its in both an authored and generated source file. Check we only applied fix-its to the hand-authored one.
                let regexMatch = try Regex(
                    "> \("Applied 3 fix-its in 1 file")" + #" \([0-9]\.[0-9]{1,3}s\)"#
                )
                #expect(stdout.contains(regexMatch))
            }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            .IssueWindowsCannotSaveAttachment,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandWhenDependencyBuildsForHostAndTarget(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "SwiftMigrate/ExistentialAnyWithCommonPluginDependencyMigration") {
                fixturePath in
                let (stdout, _) = try await execute(
                    ["migrate", "--to-feature", "ExistentialAny"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,

                )

                // Even though the CommonLibrary dependency built for both the host and destination, we should only apply a single fix-it once to its sources.
                let regexMatch = try Regex(
                    "> \("Applied 1 fix-it in 1 file")" + #" \([0-9]\.[0-9]{1,3}s\)"#
                )
                #expect(stdout.contains(regexMatch))
            }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandUpdateManifestSingleTarget(
            data: BuildData,
        ) async throws {
            try await fixture(name: "SwiftMigrate/UpdateManifest") { fixturePath in
                _ = try await execute(
                    [
                        "migrate",
                        "--to-feature",
                        "ExistentialAny,InferIsolatedConformances",
                        "--target",
                        "A",
                    ],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,

                )

                let updatedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.swift")
                )
                let expectedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.updated.targets-A.swift")
                )
                #expect(updatedManifest == expectedManifest)
            }
        }

        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandUpdateManifest2Targets(
            data: BuildData,
        ) async throws {
            try await fixture(name: "SwiftMigrate/UpdateManifest") { fixturePath in
                _ = try await execute(
                    [
                        "migrate",
                        "--to-feature",
                        "ExistentialAny,InferIsolatedConformances",
                        "--target",
                        "A,B",
                    ],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,

                )

                let updatedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.swift")
                )
                let expectedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.updated.targets-A-B.swift")
                )
                #expect(updatedManifest == expectedManifest)
            }
        }

        @Test(
            .supportsSupportedFeatures,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9006",
                relationship: .defect
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func migrateCommandUpdateManifestWithErrors(
            data: BuildData,
        ) async throws {
            try await fixture(name: "SwiftMigrate/UpdateManifest") { fixturePath in
                try await expectThrowsCommandExecutionError(
                    await execute(
                        [
                            "migrate", "--to-feature",
                            "ExistentialAny,InferIsolatedConformances,StrictMemorySafety",
                        ],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    // 'SwiftMemorySafety.strictMemorySafety' was introduced in 6.2.
                    #expect(
                        error.stderr.contains(
                            """
                            error: Could not update manifest to enable requested features for target 'A' (package manifest version 5.8.0 is too old: please update to manifest version 6.2.0 or newer)
                            error: Could not update manifest to enable requested features for target 'B' (package manifest version 5.8.0 is too old: please update to manifest version 6.2.0 or newer)
                            error: Could not update manifest to enable requested features for target 'CannotFindSettings' (unable to find array literal for 'swiftSettings' argument). Please enable them manually by adding the following Swift settings to the target: '.enableUpcomingFeature("ExistentialAny"), .enableUpcomingFeature("InferIsolatedConformances"), .strictMemorySafety()'
                            error: Could not update manifest to enable requested features for target 'CannotFindTarget' (unable to find target named 'CannotFindTarget' in package). Please enable them manually by adding the following Swift settings to the target: '.enableUpcomingFeature("ExistentialAny"), .enableUpcomingFeature("InferIsolatedConformances"), .strictMemorySafety()'
                            """
                        )
                    )
                }

                let updatedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.swift")
                )
                let expectedManifest = try localFileSystem.readFileContents(
                    fixturePath.appending(components: "Package.updated.targets-all.swift")
                )
                #expect(updatedManifest == expectedManifest)
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.BuildPlugin,
        ),
    )
    struct BuildPluginTests {
        @Test(
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func buildToolPlugin(
            data: BuildData,
        ) async throws {
            try await withKnownIssue {
                try await testBuildToolPlugin(data: data, staticStdlib: false)
            } when: {
                ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
            }
        }

        @Test(
            .requiresStdlibSupport,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func buildToolPluginWithStaticStdlib(
            data: BuildData,
        ) async throws {
            try await testBuildToolPlugin(data: data, staticStdlib: true)
        }

        func testBuildToolPlugin(data: BuildData, staticStdlib: Bool) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target and a plugin.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.writeFileContents(
                    packageDir.appending("Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            targets: [
                                .target(
                                    name: "MyLibrary",
                                    plugins: [
                                        "MyPlugin",
                                    ]
                                ),
                                .plugin(
                                    name: "MyPlugin",
                                    capability: .buildTool()
                                ),
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.swift"),
                    string:
                        """
                        public func Foo() { }
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.foo"),
                    string:
                        """
                        a file with a filename suffix handled by the plugin
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.bar"),
                    string:
                        """
                        a file with a filename suffix not handled by the plugin
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                    string:
                        """
                        import PackagePlugin
                        import Foundation
                        @main
                        struct MyBuildToolPlugin: BuildToolPlugin {
                            func createBuildCommands(
                                context: PluginContext,
                                target: Target
                            ) throws -> [Command] {
                                // Expect the initial working directory for build tool plugins is the package directory.
                                guard FileManager.default.currentDirectoryPath == context.package.directory.string else {
                                    throw "expected initial working directory ‘\\(FileManager.default.currentDirectoryPath)’"
                                }

                                // Check that the package display name is what we expect.
                                guard context.package.displayName == "MyPackage" else {
                                    throw "expected display name to be ‘MyPackage’ but found ‘\\(context.package.displayName)’"
                                }

                                // Create and return a build command that uses all the `.foo` files in the target as inputs, so they get counted as having been handled.
                                let fooFiles = target.sourceModule?.sourceFiles.compactMap{ $0.path.extension == "foo" ? $0.path : nil } ?? []
                                #if os(Windows)
                                let exec = "echo"
                                #else
                                let exec = "/bin/echo"
                                #endif
                                return [ .buildCommand(displayName: "A command", executable: Path(exec), arguments: fooFiles, inputFiles: fooFiles) ]
                            }

                        }
                        extension String : Error {}
                        """
                )

                // Invoke it, and check the results.
                let args = staticStdlib ? ["--static-swift-stdlib"] : []
                let (stdout, stderr) = try await executeSwiftBuild(
                    packageDir,
                    configuration: data.config,
                    extraArgs: args,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("Build complete!"))

                // We expect a warning about `library.bar` but not about `library.foo`.
                #expect(!stderr.contains(RelativePath("Sources/MyLibrary/library.foo").pathString))
                if data.buildSystem == .native {
                    #expect(stderr.contains("found 1 file(s) which are unhandled"))
                    #expect(stderr.contains(RelativePath("Sources/MyLibrary/library.bar").pathString))
                }
            }
        }

        @Test(
            .tags(
              .Feature.Command.Build,
              .Feature.PackageType.BuildToolPlugin
            ),
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func buildToolPluginFailure(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/Plugins/BuildToolPluginCompilationError") { packageDir in
                // Invoke it, and check the results.
                await expectThrowsCommandExecutionError(
                    try await executeSwiftBuild(
                        packageDir,
                        configuration: data.config,
                        extraArgs: ["-v"],
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    withKnownIssue {
                        #expect(error.stderr.contains("This is text from the plugin"))
                        #expect(error.stderr.contains("error: This is an error from the plugin"))
                    } when: {
                        ProcessInfo.hostOperatingSystem == .windows
                    }
                    if data.buildSystem == .native {
                        #expect(
                            error.stderr.contains("build planning stopped due to build-tool plugin failures")
                        )
                    }
                }
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.ArchiveSource,
        ),
    )
    struct ArchiveSourceTests {
        @Test(
            arguments: getBuildData(for: [BuildSystemProvider.Kind.swiftbuild]),
            [1, 2, 5]
            // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms), [1, 2, 5]
        )
        func archiveSourceWithoutArguments(
            data: BuildData,
            numberOfExecutions: Int,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")

                // Running without arguments or options, overwriting existing archive
                for num in 1...numberOfExecutions {
                    let (stdout, _) = try await execute(
                        ["archive-source"],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(
                        stdout.contains("Created Bar.zip"),
                        #"Iteration \#(num) of \#(numberOfExecutions) failed --> stdout: "\#(stdout)""#,
                    )
                }
            }
        }

        @Test(
            arguments: getBuildData(for: [BuildSystemProvider.Kind.swiftbuild]),
            // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func archiveSourceRunningWithOutputAsAbsolutePathWithingThePackageRoot(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                // Running with output as absolute path within package root
                let destination = packageRoot.appending("Bar-1.2.3.zip")
                let (stdout, _) = try await execute(
                    ["archive-source", "--output", destination.pathString],
                    packagePath: packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("Created Bar-1.2.3.zip"), #"actual: "\#(stdout)""#)
            }
        }

        @Test(
            arguments: getBuildData(for: [BuildSystemProvider.Kind.swiftbuild]),
            // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func archiveSourceRunningWithoutArgumentsOutsideThePackageRoot(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                // Running with output is outside the package root
                try await withTemporaryDirectory { tempDirectory in
                    let destination = tempDirectory.appending("Bar-1.2.3.zip")
                    let (stdout, _) = try await execute(
                        ["archive-source", "--output", destination.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout.hasPrefix("Created "), #"actual: "\#(stdout)""#)
                    #expect(stdout.contains("Bar-1.2.3.zip"), #"actual: "\#(stdout)""#)
                }
            }
        }

        @Test(
            arguments: getBuildData(for: [BuildSystemProvider.Kind.swiftbuild]),
            // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func archiveSourceRunningWithoutArgumentsInNonPackageDirectoryProducesAnError(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                // Running without arguments or options in non-package directory
                await expectThrowsCommandExecutionError(
                    try await execute(
                        ["archive-source"],
                        packagePath: fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    #expect(
                        error.stderr.contains(
                            "error: Could not find Package.swift in this directory or any of its parent directories."
                        ),
                        #"actual: "\#(stderr)""#
                    )
                }
            }
        }

        @Test(
            arguments: getBuildData(for: [BuildSystemProvider.Kind.swiftbuild]),
            // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func archiveSourceRunningWithOuboutAsAbsolutePathToExistingDirectory(
            data: BuildData,
        ) async throws {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                // Running with output as absolute path to existing directory
                let destination = AbsolutePath.root
                await expectThrowsCommandExecutionError(
                    try await execute(
                        ["archive-source", "--output", destination.pathString],
                        packagePath: packageRoot,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                ) { error in
                    let stderr = error.stderr
                    #expect(
                        stderr.contains("error: Couldn’t create an archive:"),
                        #"actual: "\#(stderr)""#
                    )
                }
            }
        }
    }

    @Suite(
        .tags(
            .Feature.Command.Package.CommandPlugin,
        ),
    )
    struct CommandPluginTests {
        struct CommandPluginTestData {
            let packageCommandArgs: CLIArguments
            let expectedStdout: [String]
        }
        @Test(
            .requiresSwiftConcurrencySupport,
            .requires(executable: "sed"),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                CommandPluginTestData(
                    // Check that we can invoke the plugin with the "plugin" subcommand.
                    packageCommandArgs: ["plugin", "mycmd"],
                    expectedStdout: [
                        "This is MyCommandPlugin."
                    ],
                ),

                CommandPluginTestData(
                    // Check that we can also invoke it without the "plugin" subcommand.
                    packageCommandArgs: ["mycmd"],
                    expectedStdout: [
                        "This is MyCommandPlugin."
                    ],
                ),
                CommandPluginTestData(
                    // Testing listing the available command plugins.
                    packageCommandArgs: ["plugin", "--list"],
                    expectedStdout: [
                        "‘mycmd’ (plugin ‘MyPlugin’ in package ‘MyPackage’)"
                    ],
                ),

                CommandPluginTestData(
                    // Check that the .docc file was properly vended to the plugin.
                    packageCommandArgs: ["mycmd", "--target", "MyLibrary"],
                    expectedStdout: [
                        "Sources/MyLibrary/library.swift: source",
                        "Sources/MyLibrary/test.docc: unknown",
                    ],
                ),
                CommandPluginTestData(
                    // Check that the .docc file was properly vended to the plugin.
                    packageCommandArgs: ["mycmd", "--target", "MyLibrary"],
                    expectedStdout: [
                        "Sources/MyLibrary/library.swift: source",
                        "Sources/MyLibrary/test.docc: unknown",
                    ],
                ),
                CommandPluginTestData(
                    // Check that information about the dependencies was properly sent to the plugin.
                    packageCommandArgs: ["mycmd", "--target", "MyLibrary"],
                    expectedStdout: [
                        "dependency HelperPackage: local"
                    ],
                ),
            ]
        )
        func commandPlugin(
            buildData: BuildData,
            testData: CommandPluginTestData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target, a plugin, and a local tool. It depends on a sample package which also has a tool.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            dependencies: [
                                .package(name: "HelperPackage", path: "VendoredDependencies/HelperPackage")
                            ],
                            targets: [
                                .target(
                                    name: "MyLibrary",
                                    dependencies: [
                                        .product(name: "HelperLibrary", package: "HelperPackage")
                                    ]
                                ),
                                .plugin(
                                    name: "MyPlugin",
                                    capability: .command(
                                        intent: .custom(verb: "mycmd", description: "What is mycmd anyway?")
                                    ),
                                    dependencies: [
                                        .target(name: "LocalBuiltTool"),
                                        .target(name: "LocalBinaryTool"),
                                        .product(name: "RemoteBuiltTool", package: "HelperPackage")
                                    ]
                                ),
                                .binaryTarget(
                                    name: "LocalBinaryTool",
                                    path: "Binaries/LocalBinaryTool.artifactbundle"
                                ),
                                .executableTarget(
                                    name: "LocalBuiltTool"
                                )
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.swift"),
                    string:
                        """
                        public func Foo() { }
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "test.docc"),
                    string:
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
                        <plist version="1.0">
                        <dict>
                            <key>CFBundleName</key>
                            <string>sample</string>
                        </dict>
                        """
                )
                let environment = Environment.current
                let hostTriple = try UserToolchain(
                    swiftSDK: .hostSwiftSDK(environment: environment),
                    environment: environment
                ).targetTriple
                let hostTripleString =
                    if hostTriple.isDarwin() {
                        hostTriple.tripleString(forPlatformVersion: "")
                    } else {
                        hostTriple.tripleString
                    }

                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "Binaries",
                        "LocalBinaryTool.artifactbundle",
                        "info.json"
                    ),
                    string: """
                        {   "schemaVersion": "1.0",
                            "artifacts": {
                                "LocalBinaryTool": {
                                    "type": "executable",
                                    "version": "1.2.3",
                                    "variants": [
                                        {   "path": "LocalBinaryTool.sh",
                                            "supportedTriples": ["\(hostTripleString)"]
                                        },
                                    ]
                                }
                            }
                        }
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "LocalBuiltTool", "main.swift"),
                    string: #"print("Hello")"#
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                    string: """
                        import PackagePlugin
                        import Foundation
                        @main
                        struct MyCommandPlugin: CommandPlugin {
                            func performCommand(
                                context: PluginContext,
                                arguments: [String]
                            ) throws {
                                print("This is MyCommandPlugin.")

                                // Print out the initial working directory so we can check it in the test.
                                print("Initial working directory: \\(FileManager.default.currentDirectoryPath)")

                                // Check that we can find a binary-provided tool in the same package.
                                print("Looking for LocalBinaryTool...")
                                let localBinaryTool = try context.tool(named: "LocalBinaryTool")
                                print("... found it at \\(localBinaryTool.path)")

                                // Check that we can find a source-built tool in the same package.
                                print("Looking for LocalBuiltTool...")
                                let localBuiltTool = try context.tool(named: "LocalBuiltTool")
                                print("... found it at \\(localBuiltTool.path)")

                                // Check that we can find a source-built tool in another package.
                                print("Looking for RemoteBuiltTool...")
                                let remoteBuiltTool = try context.tool(named: "RemoteBuiltTool")
                                print("... found it at \\(remoteBuiltTool.path)")

                                // Check that we can find a tool in the toolchain.
                                print("Looking for swiftc...")
                                let swiftc = try context.tool(named: "swiftc")
                                print("... found it at \\(swiftc.path)")

                                // Check that we can find a standard tool.
                                print("Looking for sed...")
                                let sed = try context.tool(named: "sed")
                                print("... found it at \\(sed.path)")

                                // Extract the `--target` arguments.
                                var argExtractor = ArgumentExtractor(arguments)
                                let targetNames = argExtractor.extractOption(named: "target")
                                let targets = try context.package.targets(named: targetNames)

                                // Print out the source files so that we can check them.
                                if let sourceFiles = targets.first(where: { $0.name == "MyLibrary" })?.sourceModule?.sourceFiles {
                                    for file in sourceFiles {
                                        print("  \\(file.path): \\(file.type)")
                                    }
                                }

                                // Print out the dependencies so that we can check them.
                                for dependency in context.package.dependencies {
                                    print("  dependency \\(dependency.package.displayName): \\(dependency.package.origin)")
                                }
                            }
                        }
                        """
                )

                // Create the sample vendored dependency package.
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Package.swift"
                    ),
                    string: """
                        // swift-tools-version: 5.5
                        import PackageDescription
                        let package = Package(
                            name: "HelperPackage",
                            products: [
                                .library(
                                    name: "HelperLibrary",
                                    targets: ["HelperLibrary"]
                                ),
                                .executable(
                                    name: "RemoteBuiltTool",
                                    targets: ["RemoteBuiltTool"]
                                ),
                            ],
                            targets: [
                                .target(
                                    name: "HelperLibrary"
                                ),
                                .executableTarget(
                                    name: "RemoteBuiltTool"
                                ),
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Sources",
                        "HelperLibrary",
                        "library.swift"
                    ),
                    string: "public func Bar() { }"
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Sources",
                        "RemoteBuiltTool",
                        "main.swift"
                    ),
                    string: #"print("Hello")"#
                )

                let (stdout, _) = try await execute(
                    testData.packageCommandArgs,
                    packagePath: packageDir,
                    configuration: buildData.config,
                    buildSystem: buildData.buildSystem,
                )
                for expected in testData.expectedStdout {
                    #expect(stdout.contains(expected))
                }
            }
        }
        @Test(
            .requiresSwiftConcurrencySupport,
            .requires(executable: "sed"),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginSpecialCases(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target, a plugin, and a local tool. It depends on a sample package which also has a tool.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            dependencies: [
                                .package(name: "HelperPackage", path: "VendoredDependencies/HelperPackage")
                            ],
                            targets: [
                                .target(
                                    name: "MyLibrary",
                                    dependencies: [
                                        .product(name: "HelperLibrary", package: "HelperPackage")
                                    ]
                                ),
                                .plugin(
                                    name: "MyPlugin",
                                    capability: .command(
                                        intent: .custom(verb: "mycmd", description: "What is mycmd anyway?")
                                    ),
                                    dependencies: [
                                        .target(name: "LocalBuiltTool"),
                                        .target(name: "LocalBinaryTool"),
                                        .product(name: "RemoteBuiltTool", package: "HelperPackage")
                                    ]
                                ),
                                .binaryTarget(
                                    name: "LocalBinaryTool",
                                    path: "Binaries/LocalBinaryTool.artifactbundle"
                                ),
                                .executableTarget(
                                    name: "LocalBuiltTool"
                                )
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.swift"),
                    string:
                        """
                        public func Foo() { }
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "test.docc"),
                    string:
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
                        <plist version="1.0">
                        <dict>
                            <key>CFBundleName</key>
                            <string>sample</string>
                        </dict>
                        """
                )
                let environment = Environment.current
                let hostTriple = try UserToolchain(
                    swiftSDK: .hostSwiftSDK(environment: environment),
                    environment: environment
                ).targetTriple
                let hostTripleString =
                    if hostTriple.isDarwin() {
                        hostTriple.tripleString(forPlatformVersion: "")
                    } else {
                        hostTriple.tripleString
                    }

                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "Binaries",
                        "LocalBinaryTool.artifactbundle",
                        "info.json"
                    ),
                    string: """
                        {   "schemaVersion": "1.0",
                            "artifacts": {
                                "LocalBinaryTool": {
                                    "type": "executable",
                                    "version": "1.2.3",
                                    "variants": [
                                        {   "path": "LocalBinaryTool.sh",
                                            "supportedTriples": ["\(hostTripleString)"]
                                        },
                                    ]
                                }
                            }
                        }
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "LocalBuiltTool", "main.swift"),
                    string: #"print("Hello")"#
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                    string: """
                        import PackagePlugin
                        import Foundation
                        @main
                        struct MyCommandPlugin: CommandPlugin {
                            func performCommand(
                                context: PluginContext,
                                arguments: [String]
                            ) throws {
                                print("This is MyCommandPlugin.")

                                // Print out the initial working directory so we can check it in the test.
                                print("Initial working directory: \\(FileManager.default.currentDirectoryPath)")

                                // Check that we can find a binary-provided tool in the same package.
                                print("Looking for LocalBinaryTool...")
                                let localBinaryTool = try context.tool(named: "LocalBinaryTool")
                                print("... found it at \\(localBinaryTool.path)")

                                // Check that we can find a source-built tool in the same package.
                                print("Looking for LocalBuiltTool...")
                                let localBuiltTool = try context.tool(named: "LocalBuiltTool")
                                print("... found it at \\(localBuiltTool.path)")

                                // Check that we can find a source-built tool in another package.
                                print("Looking for RemoteBuiltTool...")
                                let remoteBuiltTool = try context.tool(named: "RemoteBuiltTool")
                                print("... found it at \\(remoteBuiltTool.path)")

                                // Check that we can find a tool in the toolchain.
                                print("Looking for swiftc...")
                                let swiftc = try context.tool(named: "swiftc")
                                print("... found it at \\(swiftc.path)")

                                // Check that we can find a standard tool.
                                print("Looking for sed...")
                                let sed = try context.tool(named: "sed")
                                print("... found it at \\(sed.path)")

                                // Extract the `--target` arguments.
                                var argExtractor = ArgumentExtractor(arguments)
                                let targetNames = argExtractor.extractOption(named: "target")
                                let targets = try context.package.targets(named: targetNames)

                                // Print out the source files so that we can check them.
                                if let sourceFiles = targets.first(where: { $0.name == "MyLibrary" })?.sourceModule?.sourceFiles {
                                    for file in sourceFiles {
                                        print("  \\(file.path): \\(file.type)")
                                    }
                                }

                                // Print out the dependencies so that we can check them.
                                for dependency in context.package.dependencies {
                                    print("  dependency \\(dependency.package.displayName): \\(dependency.package.origin)")
                                }
                            }
                        }
                        """
                )

                // Create the sample vendored dependency package.
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Package.swift"
                    ),
                    string: """
                        // swift-tools-version: 5.5
                        import PackageDescription
                        let package = Package(
                            name: "HelperPackage",
                            products: [
                                .library(
                                    name: "HelperLibrary",
                                    targets: ["HelperLibrary"]
                                ),
                                .executable(
                                    name: "RemoteBuiltTool",
                                    targets: ["RemoteBuiltTool"]
                                ),
                            ],
                            targets: [
                                .target(
                                    name: "HelperLibrary"
                                ),
                                .executableTarget(
                                    name: "RemoteBuiltTool"
                                ),
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Sources",
                        "HelperLibrary",
                        "library.swift"
                    ),
                    string: "public func Bar() { }"
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage",
                        "Sources",
                        "RemoteBuiltTool",
                        "main.swift"
                    ),
                    string: #"print("Hello")"#
                )

                // Check that we get the expected error if trying to invoke a plugin with the wrong name.
                do {
                    await expectThrowsCommandExecutionError(
                        try await execute(
                            ["my-nonexistent-cmd"],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        // guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                        //     Issue.record("invalid error \(error)")
                        //     return
                        // }
                        #expect(error.stderr.contains("Unknown subcommand or plugin name ‘my-nonexistent-cmd’"))
                    }
                }
                do {
                    // Check that the initial working directory is what we expected.
                    let workingDirectory = FileManager.default.currentDirectoryPath
                    let (stdout, _) = try await execute(
                        ["mycmd"],
                        packagePath: packageDir,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout.contains("Initial working directory: \(workingDirectory)"))
                }
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func ambiguousCommandPlugin(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/Plugins/AmbiguousCommands") { fixturePath in
                let (stdout, _) = try await execute(
                    ["plugin", "--package", "A", "A"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("Hello A!"))
            }
        }

        // Test reporting of plugin diagnostic messages at different verbosity levels
        @Test(
            .tags(
              .Feature.Command.Build,
              .Feature.PackageType.CommandPlugin
            ),
            .requiresSwiftConcurrencySupport,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/8180",
                relationship: .defect
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginDiagnostics(
            data: BuildData,
        ) async throws {

            // Match patterns for expected messages
            let isEmpty = ""
            let isOnlyPrint = "command plugin: print\n"
            let containsProgress = "[diagnostics-stub] command plugin: Diagnostics.progress"
            let containsRemark = "command plugin: Diagnostics.remark"
            let containsWarning = "command plugin: Diagnostics.warning"
            let containsError = "command plugin: Diagnostics.error"

            await withKnownIssue(isIntermittent: true) {
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    func runPlugin(
                        flags: [String],
                        diagnostics: [String],
                        completion: (String, String) -> Void
                    ) async throws {
                        let (stdout, stderr) = try await execute(
                            flags + ["print-diagnostics"] + diagnostics,
                            packagePath: fixturePath,
                            env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        completion(stdout, stderr)
                    }

                    // Diagnostics.error causes SwiftPM to return a non-zero exit code, but we still need to check stdout and stderr
                    func runPluginWithError(
                        flags: [String],
                        diagnostics: [String],
                        completion: (String, String) -> Void
                    ) async throws {
                        await expectThrowsCommandExecutionError(
                            try await execute(
                                flags + ["print-diagnostics"] + diagnostics,
                                packagePath: fixturePath,
                                env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                                configuration: data.config,
                                buildSystem: data.buildSystem,
                            )
                        ) { error in
                            // guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                            //     Issue.record("invalid error \(error)")
                            //     return
                            // }
                            completion(error.stdout, error.stderr)
                        }
                    }

                    // Default verbosity
                    //   - stdout is always printed
                    //   - Diagnostics below 'warning' are suppressed

                    try await runPlugin(flags: [], diagnostics: ["print"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        let filteredStderr = stderr.components(separatedBy: "\n")
                            .filter { !$0.contains("Unable to locate libSwiftScan") }.joined(separator: "\n")
                        #expect(filteredStderr == isEmpty)
                    }

                    try await runPlugin(flags: [], diagnostics: ["print", "progress"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPlugin(flags: [], diagnostics: ["print", "progress", "remark"]) {
                        stdout,
                        stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPlugin(flags: [], diagnostics: ["print", "progress", "remark", "warning"]) {
                        stdout,
                        stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(stderr.contains(containsWarning))
                    }

                    try await runPluginWithError(
                        flags: [],
                        diagnostics: ["print", "progress", "remark", "warning", "error"]
                    ) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(stderr.contains(containsWarning))
                        #expect(stderr.contains(containsError))
                    }

                    // Quiet Mode
                    //   - stdout is always printed
                    //   - Diagnostics below 'error' are suppressed

                    try await runPlugin(flags: ["-q"], diagnostics: ["print"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        let filteredStderr = stderr.components(separatedBy: "\n")
                            .filter { !$0.contains("Unable to locate libSwiftScan") }.joined(separator: "\n")
                        #expect(filteredStderr == isEmpty)
                    }

                    try await runPlugin(flags: ["-q"], diagnostics: ["print", "progress"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPlugin(flags: ["-q"], diagnostics: ["print", "progress", "remark"]) {
                        stdout,
                        stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPlugin(
                        flags: ["-q"],
                        diagnostics: ["print", "progress", "remark", "warning"]
                    ) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPluginWithError(
                        flags: ["-q"],
                        diagnostics: ["print", "progress", "remark", "warning", "error"]
                    ) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(!stderr.contains(containsRemark))
                        #expect(!stderr.contains(containsWarning))
                        #expect(stderr.contains(containsError))
                    }

                    // Verbose Mode
                    //   - stdout is always printed
                    //   - All diagnostics are printed
                    //   - Substantial amounts of additional compiler output are also printed

                    try await runPlugin(flags: ["-v"], diagnostics: ["print"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        // At this level stderr contains extra compiler output even if the plugin does not print diagnostics
                    }

                    try await runPlugin(flags: ["-v"], diagnostics: ["print", "progress"]) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                    }

                    try await runPlugin(flags: ["-v"], diagnostics: ["print", "progress", "remark"]) {
                        stdout,
                        stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(stderr.contains(containsRemark))
                    }

                    try await runPlugin(
                        flags: ["-v"],
                        diagnostics: ["print", "progress", "remark", "warning"]
                    ) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(stderr.contains(containsRemark))
                        #expect(stderr.contains(containsWarning))
                    }

                    try await runPluginWithError(
                        flags: ["-v"],
                        diagnostics: ["print", "progress", "remark", "warning", "error"]
                    ) { stdout, stderr in
                        #expect(stdout == isOnlyPrint)
                        #expect(stderr.contains(containsProgress))
                        #expect(stderr.contains(containsRemark))
                        #expect(stderr.contains(containsWarning))
                        #expect(stderr.contains(containsError))
                    }
                }
            }
        }

        // Test target builds requested by a command plugin
        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginTargetBuilds_BinaryIsBuildinDebugByDefault(
            buildData: BuildData,
        ) async throws {
            let debugTarget = try buildData.buildSystem.binPath(for: .debug) + [executableName("placeholder")]
            let releaseTarget = try buildData.buildSystem.binPath(for: .release) + [executableName("placeholder")]
            try await withKnownIssue {
                // By default, a plugin-requested build produces a debug binary
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = try await execute(
                        ["build-target"],
                        packagePath: fixturePath,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    expectFileIsExecutable(at: fixturePath.appending(components: debugTarget), "build-target")
                    expectFileDoesNotExists(
                        at: fixturePath.appending(components: releaseTarget),
                        "build-target build-inherit"
                    )
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        // Test target builds requested by a command plugin
        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginTargetBuilds_BinaryWillBeBuiltInDebugIfPluginSpecifiesDebugBuild(
            buildData: BuildData,
        ) async throws {
            let debugTarget = try buildData.buildSystem.binPath(for: .debug) + [executableName("placeholder")]
            let releaseTarget = try buildData.buildSystem.binPath(for: .release) + [executableName("placeholder")]
            try await withKnownIssue {
                // If the plugin specifies a debug binary, that is what will be built, regardless of overall configuration
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = try await execute(
                        ["build-target", "build-debug"],
                        packagePath: fixturePath,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    expectFileIsExecutable(
                        at: fixturePath.appending(components: debugTarget),
                        "build-target build-debug"
                    )
                    expectFileDoesNotExists(
                        at: fixturePath.appending(components: releaseTarget),
                        "build-target build-inherit"
                    )
                }

            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        // Test target builds requested by a command plugin
        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginTargetBuilds_BinaryWillBeBuiltInReleaseIfPluginSpecifiesReleaseBuild(
            buildData: BuildData,
        ) async throws {
            let debugTarget = try buildData.buildSystem.binPath(for: .debug) + [executableName("placeholder")]
            let releaseTarget = try buildData.buildSystem.binPath(for: .release) + [executableName("placeholder")]
            try await withKnownIssue {
                // If the plugin requests a release binary, that is what will be built, regardless of overall configuration
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = try await execute(
                        ["build-target", "build-release"],
                        packagePath: fixturePath,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    expectFileDoesNotExists(
                        at: fixturePath.appending(components: debugTarget),
                        "build-target build-inherit"
                    )
                    expectFileIsExecutable(
                        at: fixturePath.appending(components: releaseTarget),
                        "build-target build-release"
                    )
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        // Test target builds requested by a command plugin
        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginTargetBuilds_BinaryWillBeBuiltCorrectlyIfPluginSpecifiesInheritBuild(
            buildData: BuildData,
        ) async throws {
            let debugTarget = try buildData.buildSystem.binPath(for: .debug) + [executableName("placeholder")]
            let releaseTarget = try buildData.buildSystem.binPath(for: .release) + [executableName("placeholder")]
            try await withKnownIssue {
                // If the plugin inherits the overall build configuration, that is what will be built
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = try await execute(
                        ["build-target", "build-inherit"],
                        packagePath: fixturePath,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    let fileShouldNotExist: AbsolutePath
                    let fileShouldExist: AbsolutePath
                    switch buildData.config {
                    case .debug:
                        fileShouldExist = fixturePath.appending(components: debugTarget)
                        fileShouldNotExist = fixturePath.appending(components: releaseTarget)
                    case .release:
                        fileShouldNotExist = fixturePath.appending(components: debugTarget)
                        fileShouldExist = fixturePath.appending(components: releaseTarget)
                    }
                    expectFileDoesNotExists(at: fileShouldNotExist, "build-target build-inherit")
                    expectFileIsExecutable(at: fileShouldExist, "build-target build-inherit")
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginBuildTestabilityInternal_ModuleDebug_True(
            data: BuildData,
        ) async throws {
            // Plugin arguments: check-testability <targetName> <config> <shouldTestable>
            try await withKnownIssue {
                // Overall configuration: debug, plugin build request: debug -> without testability
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = await #expect(throws: Never.self) {
                        try await execute(
                            ["check-testability", "InternalModule", "debug", "true"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginBuildTestabilityInternalModule_Release_False(
            data: BuildData,
        ) async throws {
            try await withKnownIssue {
                // Overall configuration: debug, plugin build request: release -> without testability
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = await #expect(throws: Never.self) {
                        try await execute(
                            ["check-testability", "InternalModule", "release", "false"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .tags(
              .Feature.Command.Run,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginBuildTestabilityAllWithTests_Release_True(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: (ProcessInfo.hostOperatingSystem == .linux)) {
                // Overall configuration: release, plugin build request: release including tests -> with testability
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let _ = await #expect(throws: Never.self) {
                        try await execute(
                            ["check-testability", "all-with-tests", "release", "true"],
                            packagePath: fixturePath,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
                    || (ProcessInfo.hostOperatingSystem == .linux && data.buildSystem == .swiftbuild)
            }
        }

        // Test logging of builds initiated by a command plugin
        @Test(
            .tags(
              .Feature.Command.Build,
              .Feature.PackageType.CommandPlugin
            ),
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginBuildLogs(
            data: BuildData,
        ) async throws {

            // Match patterns for expected messages
            let isEmpty = ""

            // result.logText printed by the plugin has a prefix
            let containsLogtext =
                "command plugin: packageManager.build logtext: Building for debugging..."

            // Echoed logs have no prefix
            let containsLogecho = "Building for debugging...\n"

            // These tests involve building a target, so each test must run with a fresh copy of the fixture
            // otherwise the logs may be different in subsequent tests.

            // Check than nothing is echoed when echoLogs is false
            try await withKnownIssue(isIntermittent: ProcessInfo.hostOperatingSystem == .windows) {
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let (stdout, stderr) = try await execute(  //got here
                        ["print-diagnostics", "build"],
                        packagePath: fixturePath,
                        env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout == isEmpty)
                    // Filter some unrelated output that could show up on stderr.
                    let filteredStderr = stderr.components(separatedBy: "\n")
                        .filter { !$0.contains("Unable to locate libSwiftScan") }
                        .filter { !($0.contains("warning: ") && $0.contains("unable to find libclang")) }
                        .joined(separator: "\n")
                    #expect(filteredStderr == isEmpty)
                }

                // Check that logs are returned to the plugin when echoLogs is false
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let (stdout, stderr) = try await execute(  // got here
                        ["print-diagnostics", "build", "printlogs"],
                        packagePath: fixturePath,
                        env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout.contains(containsLogtext))
                    // Filter some unrelated output that could show up on stderr.
                    let filteredStderr = stderr.components(separatedBy: "\n")
                        .filter { !$0.contains("Unable to locate libSwiftScan") }
                        .filter { !($0.contains("warning: ") && $0.contains("unable to find libclang")) }
                        .joined(separator: "\n")
                    #expect(filteredStderr == isEmpty)
                }

                // Check that logs echoed to the console (on stderr) when echoLogs is true
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let (stdout, stderr) = try await execute(
                        ["print-diagnostics", "build", "echologs"],
                        packagePath: fixturePath,
                        env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout == isEmpty)
                    #expect(stderr.contains(containsLogecho))
                }

                // Check that logs are returned to the plugin and echoed to the console (on stderr) when echoLogs is true
                try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
                    let (stdout, stderr) = try await execute(
                        ["print-diagnostics", "build", "printlogs", "echologs"],
                        packagePath: fixturePath,
                        env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                    #expect(stdout.contains(containsLogtext))
                    #expect(stderr.contains(containsLogecho))
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }

        }

        private static let allNetworkConnectionPermissionError = "all network connections on ports: 1, 2, 3"
        struct CommandPluginNetworkingPermissionsTestData {
            let permissionsManifestFragment: String
            let permissionError: String
            let reason: String
            let remedy: CLIArguments
        }
        fileprivate static func getCommandPluginNetworkingPermissionTestData()
            -> [CommandPluginNetworkingPermissionsTestData]
        {
            [
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .all(), reason: \"internet good\")]",
                    permissionError: "all network connections on all ports",
                    reason: "internet good",
                    remedy: ["--allow-network-connections", "all"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .all(ports: [23, 42, 443, 8080]), reason: \"internet good\")]",
                    permissionError: "all network connections on ports: 23, 42, 443, 8080",
                    reason: "internet good",
                    remedy: ["--allow-network-connections", "all:23,42,443,8080"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .all(ports: 1..<4), reason: \"internet good\")]",
                    permissionError: Self.allNetworkConnectionPermissionError,
                    reason: "internet good",
                    remedy: ["--allow-network-connections", "all:1,2,3"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .local(), reason: \"localhost good\")]",
                    permissionError: "local network connections on all ports",
                    reason: "localhost good",
                    remedy: ["--allow-network-connections", "local"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .local(ports: [23, 42, 443, 8080]), reason: \"localhost good\")]",
                    permissionError: "local network connections on ports: 23, 42, 443, 8080",
                    reason: "localhost good",
                    remedy: ["--allow-network-connections", "local:23,42,443,8080"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .local(ports: 1..<4), reason: \"localhost good\")]",
                    permissionError: "local network connections on ports: 1, 2, 3",
                    reason: "localhost good",
                    remedy: ["--allow-network-connections", "local:1,2,3"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .docker, reason: \"docker good\")]",
                    permissionError: "docker unix domain socket connections",
                    reason: "docker good",
                    remedy: ["--allow-network-connections", "docker"],
                ),
                CommandPluginNetworkingPermissionsTestData(
                    permissionsManifestFragment:
                        "[.allowNetworkConnections(scope: .unixDomainSocket, reason: \"unix sockets good\")]",
                    permissionError: "unix domain socket connections",
                    reason: "unix sockets good",
                    remedy: ["--allow-network-connections", "unixDomainSocket"],
                ),
            ]
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .requireHostOS(.macOS),
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            Self.getCommandPluginNetworkingPermissionTestData()
        )
        func commandPluginNetworkingPermissionsWithoutUsingRemedy(
            buildData: BuildData,
            testData: CommandPluginNetworkingPermissionsTestData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target and a plugin.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Package.swift"),
                    string:
                        """
                        // swift-tools-version: 5.9
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            targets: [
                                .target(name: "MyLibrary"),
                                .plugin(name: "MyPlugin", capability: .command(intent: .custom(verb: "Network", description: "Help description"), permissions: \(testData.permissionsManifestFragment))),
                            ]
                        )
                        """
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Sources", "MyLibrary", "library.swift"),
                    string: "public func Foo() { }"
                )
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                    string:
                        """
                        import PackagePlugin

                        @main
                        struct MyCommandPlugin: CommandPlugin {
                            func performCommand(context: PluginContext, arguments: [String]) throws {
                                print("hello world")
                            }
                        }
                        """
                )

                await expectThrowsCommandExecutionError(
                    try await execute(
                        ["plugin", "Network"],
                        packagePath: packageDir,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                ) { error in
                    #expect(!error.stdout.contains("hello world"))
                    #expect(
                        error.stderr.contains(
                            "error: Plugin ‘MyPlugin’ wants permission to allow \(testData.permissionError)."
                        )
                    )
                    #expect(error.stderr.contains("Stated reason: “\(testData.reason)”."))
                    #expect(
                        error.stderr.contains("Use `\(testData.remedy.joined(separator: " "))` to allow this.")
                    )
                }
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Run,
                .Feature.Command.Package.CommandPlugin,
            ),
            .IssueWindowsRelativePathAssert,
            .IssueWindowsLongPath,
            .IssueWindowsPathLastComponent,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9083",
                relationship: .defect,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            Self.getCommandPluginNetworkingPermissionTestData()
        )
        func commandPluginNetworkingPermissionsUsingRemedy(
            buildData: BuildData,
            testData: CommandPluginNetworkingPermissionsTestData,
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a library target and a plugin.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string:
                            """
                            // swift-tools-version: 5.9
                            import PackageDescription
                            let package = Package(
                                name: "MyPackage",
                                targets: [
                                    .target(name: "MyLibrary"),
                                    .plugin(name: "MyPlugin", capability: .command(intent: .custom(verb: "Network", description: "Help description"), permissions: \(testData.permissionsManifestFragment))),
                                ]
                            )
                            """
                    )
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Sources", "MyLibrary", "library.swift"),
                        string: "public func Foo() { }"
                    )
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift"),
                        string:
                            """
                            import PackagePlugin

                            @main
                            struct MyCommandPlugin: CommandPlugin {
                                func performCommand(context: PluginContext, arguments: [String]) throws {
                                    print("hello world")
                                }
                            }
                            """
                    )

                    // Check that we don't get an error (and also are allowed to write to the package directory) if we pass `--allow-writing-to-package-directory`.
                    do {
                        let (stdout, _) = try await execute(
                            ["plugin"] + testData.remedy + ["Network"],
                            packagePath: packageDir,
                            configuration: buildData.config,
                            buildSystem: buildData.buildSystem,
                        )
                        withKnownIssue(isIntermittent: true) {
                            #expect(stdout.contains("hello world"))
                        } when: {
                            ProcessInfo.hostOperatingSystem == .windows && buildData.buildSystem == .swiftbuild && buildData.config == .debug && testData.permissionError == Self.allNetworkConnectionPermissionError
                        }
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/8782",
                relationship: .defect
            ),
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/9090",
                relationship: .defect,
            ),
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginPermissions(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a library target and a plugin.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.createDirectory(packageDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string:
                            """
                            // swift-tools-version: 5.6
                            import PackageDescription
                            import Foundation
                            let package = Package(
                                name: "MyPackage",
                                targets: [
                                    .target(
                                        name: "MyLibrary"
                                    ),
                                    .plugin(
                                        name: "MyPlugin",
                                        capability: .command(
                                            intent: .custom(verb: "PackageScribbler", description: "Help description"),
                                            // We use an environment here so we can control whether we declare the permission.
                                            permissions: ProcessInfo.processInfo.environment["DECLARE_PACKAGE_WRITING_PERMISSION"] == "1"
                                                ? [.writeToPackageDirectory(reason: "For testing purposes")]
                                                : []
                                        )
                                    ),
                                ]
                            )
                            """
                    )
                    let libPath = packageDir.appending(components: "Sources", "MyLibrary")
                    try localFileSystem.createDirectory(libPath, recursive: true)
                    try localFileSystem.writeFileContents(
                        libPath.appending("library.swift"),
                        string:
                            "public func Foo() { }"
                    )
                    let pluginPath = packageDir.appending(components: "Plugins", "MyPlugin")
                    try localFileSystem.createDirectory(pluginPath, recursive: true)
                    try localFileSystem.writeFileContents(
                        pluginPath.appending("plugin.swift"),
                        string:
                            """
                            import PackagePlugin
                            import Foundation

                            @main
                            struct MyCommandPlugin: CommandPlugin {
                                func performCommand(
                                    context: PluginContext,
                                    arguments: [String]
                                ) throws {
                                    // Check that we can write to the package directory.
                                    print("Trying to write to the package directory...")
                                    guard FileManager.default.createFile(atPath: context.package.directory.appending("Foo").string, contents: Data("Hello".utf8)) else {
                                        throw "Couldn’t create file at path \\(context.package.directory.appending("Foo"))"
                                    }
                                    print("... successfully created it")
                                }
                            }
                            extension String: Error {}
                            """
                    )

                    // Check that we get an error if the plugin needs permission but if we don't give it to them. Note that sandboxing is only currently supported on macOS.
                    #if os(macOS)
                        do {
                            await expectThrowsCommandExecutionError(
                                try await execute(
                                    ["plugin", "PackageScribbler"],
                                    packagePath: packageDir,
                                    env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "1"],
                                    configuration: data.config,
                                    buildSystem: data.buildSystem,
                                )
                            ) { error in
                                // guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                                //     return Issue.record("invalid error \(error)")
                                // }
                                #expect(!error.stdout.contains("successfully created it"))
                                #expect(
                                    error.stderr.contains(
                                        "error: Plugin ‘MyPlugin’ wants permission to write to the package directory."
                                    )
                                )
                                #expect(error.stderr.contains("Stated reason: “For testing purposes”."))
                                #expect(
                                    error.stderr.contains("Use `--allow-writing-to-package-directory` to allow this.")
                                )
                            }
                        }
                    #endif

                    // Check that we don't get an error (and also are allowed to write to the package directory) if we pass `--allow-writing-to-package-directory`.
                    do {
                        let (stdout, stderr) = try await execute(
                            ["plugin", "--allow-writing-to-package-directory", "PackageScribbler"],
                            packagePath: packageDir,
                            env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "1"],
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        withKnownIssue(isIntermittent: true) {
                            #expect(stdout.contains("successfully created it"))
                        } when: {
                            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .native && data.config == .release
                        }
                        #expect(!stderr.contains("error: Couldn’t create file at path"))
                    }

                    // Check that we get an error if the plugin doesn't declare permission but tries to write anyway. Note that sandboxing is only currently supported on macOS.
                    #if os(macOS)
                        do {
                            await expectThrowsCommandExecutionError(
                                try await execute(
                                    ["plugin", "PackageScribbler"],
                                    packagePath: packageDir,
                                    env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "0"],
                                    configuration: data.config,
                                    buildSystem: data.buildSystem,
                                )
                            ) { error in
                                // guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                                //     Issue.record("invalid error \(error)")
                                //     return
                                // }
                                #expect(!error.stdout.contains("successfully created it"))
                                #expect(error.stderr.contains("error: Couldn’t create file at path"))
                            }
                        }
                    #endif

                    // Check default command with arguments
                    do {
                        let (stdout, stderr) = try await execute(
                            ["--allow-writing-to-package-directory", "PackageScribbler"],
                            packagePath: packageDir,
                            env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "1"],
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("successfully created it"))
                        #expect(!stderr.contains("error: Couldn’t create file at path"))
                    }

                    // Check plugin arguments after plugin name
                    do {
                        let (stdout, stderr) = try await execute(
                            ["plugin", "PackageScribbler", "--allow-writing-to-package-directory"],
                            packagePath: packageDir,
                            env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "1"],
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("successfully created it"))
                        #expect(!stderr.contains("error: Couldn’t create file at path"))
                    }

                    // Check default command with arguments after plugin name
                    do {
                        let (stdout, stderr) = try await execute(
                            ["PackageScribbler", "--allow-writing-to-package-directory"],
                            packagePath: packageDir,
                            env: ["DECLARE_PACKAGE_WRITING_PERMISSION": "1"],
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("successfully created it"))
                        #expect(!stderr.contains("error: Couldn’t create file at path"))
                    }
                }
            } when: {
                ProcessInfo.processInfo.environment["SWIFTCI_EXHIBITS_GH_8782"] != nil
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                true,  // check argument
                false,  // check default argument
            ]
        )
        func commandPluginArgumentsNotSwallowed(
            data: BuildData,
            _ checkArgument: Bool,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target and a plugin.
                let packageDir = tmpPath.appending(components: "MyPackage")

                try localFileSystem.createDirectory(packageDir)
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Package.swift"),
                    string: """
                        // swift-tools-version: 5.6
                        import PackageDescription
                        import Foundation
                        let package = Package(
                            name: "MyPackage",
                            targets: [
                                .plugin(
                                    name: "MyPlugin",
                                    capability: .command(
                                        intent: .custom(verb: "MyPlugin", description: "Help description")
                                    )
                                ),
                            ]
                        )
                        """
                )

                let pluginDir = packageDir.appending(components: "Plugins", "MyPlugin")
                try localFileSystem.createDirectory(pluginDir, recursive: true)
                try localFileSystem.writeFileContents(
                    pluginDir.appending("plugin.swift"),
                    string: """
                        import PackagePlugin
                        import Foundation

                        @main
                        struct MyCommandPlugin: CommandPlugin {
                            func performCommand(
                                context: PluginContext,
                                arguments: [String]
                            ) throws {
                                print (arguments)
                                guard arguments.contains("--foo") else {
                                    throw "expecting argument foo"
                                }
                                guard arguments.contains("--help") else {
                                    throw "expecting argument help"
                                }
                                guard arguments.contains("--version") else {
                                    throw "expecting argument version"
                                }
                                guard arguments.contains("--verbose") else {
                                    throw "expecting argument verbose"
                                }
                                print("success")
                            }
                        }
                        extension String: Error {}
                        """
                )

                let commandPrefix = checkArgument ? ["plugin"] : []
                let (stdout, stderr) = try await execute(
                    commandPrefix + ["MyPlugin", "--foo", "--help", "--version", "--verbose"],
                    packagePath: packageDir,
                    env: ["SWIFT_DRIVER_SWIFTSCAN_LIB": "/this/is/a/bad/path"],
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(stdout.contains("success"))
                #expect(!stderr.contains("error:"))
            }
        }

        @Test(
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            // Depending on how the test is running, the `swift-symbolgraph-extract` tool might be unavailable.
            .requiresSymbolgraphExtract,
            .issue(
                "https://github.com/swiftlang/swift-package-manager/issues/8848",
                relationship: .defect
            ),
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginSymbolGraphCallbacks(
            data: BuildData,
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a library, and executable, and a plugin.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.createDirectory(packageDir)
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string: """
                            // swift-tools-version: 5.6
                            import PackageDescription
                            let package = Package(
                                name: "MyPackage",
                                targets: [
                                    .target(
                                        name: "MyLibrary"
                                    ),
                                    .executableTarget(
                                        name: "MyCommand",
                                        dependencies: ["MyLibrary"]
                                    ),
                                    .plugin(
                                        name: "MyPlugin",
                                        capability: .command(
                                            intent: .documentationGeneration()
                                        )
                                    ),
                                ]
                            )
                            """
                    )

                    let libraryPath = packageDir.appending(
                        components: "Sources",
                        "MyLibrary",
                        "library.swift"
                    )
                    try localFileSystem.createDirectory(libraryPath.parentDirectory, recursive: true)
                    try localFileSystem.writeFileContents(
                        libraryPath,
                        string: #"public func GetGreeting() -> String { return "Hello" }"#
                    )

                    let commandPath = packageDir.appending(components: "Sources", "MyCommand", "main.swift")
                    try localFileSystem.createDirectory(commandPath.parentDirectory, recursive: true)
                    try localFileSystem.writeFileContents(
                        commandPath,
                        string: """
                            import MyLibrary
                            print("\\(GetGreeting()), World!")
                            """
                    )

                    let pluginPath = packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift")
                    try localFileSystem.createDirectory(pluginPath.parentDirectory, recursive: true)
                    try localFileSystem.writeFileContents(
                        pluginPath,
                        string: """
                            import PackagePlugin
                            import Foundation

                            @main
                            struct MyCommandPlugin: CommandPlugin {
                                func performCommand(
                                    context: PluginContext,
                                    arguments: [String]
                                ) throws {
                                    // Ask for and print out the symbol graph directory for each target.
                                    var argExtractor = ArgumentExtractor(arguments)
                                    let targetNames = argExtractor.extractOption(named: "target")
                                    let targets = targetNames.isEmpty
                                        ? context.package.targets
                                        : try context.package.targets(named: targetNames)
                                    for target in targets {
                                        #if compiler(>=6.3)
                                        let symbolGraph = try packageManager.getSymbolGraph(for: target,
                                            options: .init(minimumAccessLevel: .public, includeInheritedDocs: false))
                                        #else
                                        let symbolGraph = try packageManager.getSymbolGraph(for: target,
                                            options: .init(minimumAccessLevel: .public))
                                        #endif
                                        print("\\(target.name): \\(symbolGraph.directoryPath)")
                                    }
                                }
                            }
                            """
                    )

                    // Check that if we don't pass any target, we successfully get symbol graph information for all targets in the package, and at different paths.
                    do {
                        let (stdout, _) = try await execute(
                            ["generate-documentation"],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        switch data.buildSystem {
                        case .native:
                            #expect(stdout.contains("MyLibrary:"))
                            #expect(stdout.contains(AbsolutePath("/mypackage/MyLibrary").pathString))
                            #expect(stdout.contains("MyCommand:"))
                            #expect(stdout.contains(AbsolutePath("/mypackage/MyCommand").pathString))
                        case .swiftbuild:
                            #expect(stdout.contains("MyLibrary:"))
                            #expect(stdout.contains(AbsolutePath("/MyLibrary.symbolgraphs").pathString))
                            #expect(stdout.contains("MyCommand:"))
                            #expect(stdout.contains(AbsolutePath("/MyCommand.symbolgraphs").pathString))
                        case .xcode:
                            Issue.record("Test expectations are not defined")
                        }
                    }

                    // Check that if we pass a target, we successfully get symbol graph information for just the target we asked for.
                    do {
                        let (stdout, _) = try await execute(
                            ["generate-documentation", "--target", "MyLibrary"],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        switch data.buildSystem {
                        case .native:
                            #expect(stdout.contains("MyLibrary:"))
                            #expect(stdout.contains(AbsolutePath("/mypackage/MyLibrary").pathString))
                            #expect(!stdout.contains("MyCommand:"))
                            #expect(!stdout.contains(AbsolutePath("/mypackage/MyCommand").pathString))
                        case .swiftbuild:
                            #expect(stdout.contains("MyLibrary:"))
                            #expect(stdout.contains(AbsolutePath("/MyLibrary.symbolgraphs").pathString))
                            #expect(!stdout.contains("MyCommand:"))
                            #expect(!stdout.contains(AbsolutePath("/MyCommand.symbolgraphs").pathString))
                        case .xcode:
                            Issue.record("Test expectations are not defined")
                        }
                    }
                }
            } when: {
                let shouldSkip: Bool = (ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild)
                    || !CiEnvironment.runningInSmokeTestPipeline

                #if compiler(>=6.3)
                    return shouldSkip
                #else
                    // Symbol graph generation options are only available in 6.3 toolchain or later for swift build
                    return shouldSkip || data.buildSystem == .swiftbuild
                #endif
            }
        }

        @Test(
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginBuildingCallbacks(
            data: BuildData,
        ) async throws {
            try await withKnownIssue {
                try await testWithTemporaryDirectory { tmpPath in
                    let buildSystemProvider = data.buildSystem
                    // Create a sample package with a library, an executable, and a command plugin.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.createDirectory(packageDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string: """
                            // swift-tools-version: 5.6
                            import PackageDescription
                            let package = Package(
                                name: "MyPackage",
                                products: [
                                    .library(
                                        name: "MyAutomaticLibrary",
                                        targets: ["MyLibrary"]
                                    ),
                                    .library(
                                        name: "MyStaticLibrary",
                                        type: .static,
                                        targets: ["MyLibrary"]
                                    ),
                                    .library(
                                        name: "MyDynamicLibrary",
                                        type: .dynamic,
                                        targets: ["MyLibrary"]
                                    ),
                                    .executable(
                                        name: "MyExecutable",
                                        targets: ["MyExecutable"]
                                    ),
                                ],
                                targets: [
                                    .target(
                                        name: "MyLibrary"
                                    ),
                                    .executableTarget(
                                        name: "MyExecutable",
                                        dependencies: ["MyLibrary"]
                                    ),
                                    .plugin(
                                        name: "MyPlugin",
                                        capability: .command(
                                            intent: .custom(verb: "my-build-tester", description: "Help description")
                                        )
                                    ),
                                ]
                            )
                            """
                    )
                    let myPluginTargetDir = packageDir.appending(components: "Plugins", "MyPlugin")
                    try localFileSystem.createDirectory(myPluginTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myPluginTargetDir.appending("plugin.swift"),
                        string: """
                            import PackagePlugin
                            @main
                            struct MyCommandPlugin: CommandPlugin {
                                func performCommand(
                                    context: PluginContext,
                                    arguments: [String]
                                ) throws {
                                    // Extract the plugin arguments.
                                    var argExtractor = ArgumentExtractor(arguments)
                                    let productNames = argExtractor.extractOption(named: "product")
                                    if productNames.count != 1 {
                                        throw "Expected exactly one product name, but had: \\(productNames.joined(separator: ", "))"
                                    }
                                    let products = try context.package.products(named: productNames)
                                    let printCommands = (argExtractor.extractFlag(named: "print-commands") > 0)
                                    let release = (argExtractor.extractFlag(named: "release") > 0)
                                    if let unextractedArgs = argExtractor.unextractedOptionsOrFlags.first {
                                        throw "Unknown option: \\(unextractedArgs)"
                                    }
                                    let positionalArgs = argExtractor.remainingArguments
                                    if !positionalArgs.isEmpty {
                                        throw "Unexpected extra arguments: \\(positionalArgs)"
                                    }
                                    do {
                                        var parameters = PackageManager.BuildParameters()
                                        parameters.configuration = release ? .release : .debug
                                        parameters.logging = printCommands ? .verbose : .concise
                                        parameters.otherSwiftcFlags = ["-DEXTRA_SWIFT_FLAG"]
                                        let result = try packageManager.build(.product(products[0].name), parameters: parameters)
                                        print("succeeded: \\(result.succeeded)")
                                        for artifact in result.builtArtifacts {
                                            print("artifact-path: \\(artifact.path.string)")
                                            print("artifact-kind: \\(artifact.kind)")
                                        }
                                        print("log:\\n\\(result.logText)")
                                    }
                                    catch {
                                        print("error from the plugin host: \\(error)")
                                    }
                                }
                            }
                            extension String: Error {}
                            """
                    )
                    let myLibraryTargetDir = packageDir.appending(components: "Sources", "MyLibrary")
                    try localFileSystem.createDirectory(myLibraryTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myLibraryTargetDir.appending("library.swift"),
                        string: """
                            public func GetGreeting() -> String { return "Hello" }
                            """
                    )
                    let myExecutableTargetDir = packageDir.appending(components: "Sources", "MyExecutable")
                    try localFileSystem.createDirectory(myExecutableTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myExecutableTargetDir.appending("main.swift"),
                        string: """
                            import MyLibrary
                            print("\\(GetGreeting()), World!")
                            """
                    )

                    // Invoke the plugin with parameters choosing a verbose build of MyExecutable for debugging.
                    do {
                        let (stdout, _) = try await execute(
                            ["my-build-tester", "--product", "MyExecutable", "--print-commands"],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("Building for debugging..."))
                        if buildSystemProvider == .native {
                            #expect(stdout.contains("-module-name MyExecutable"))
                            #expect(stdout.contains("-DEXTRA_SWIFT_FLAG"))
                            #expect(stdout.contains("Build of product 'MyExecutable' complete!"))
                        }
                        #expect(stdout.contains("succeeded: true"))
                        switch buildSystemProvider {
                        case .native:
                            #expect(stdout.contains("artifact-path:"))
                            #expect(stdout.contains(RelativePath("debug/MyExecutable").pathString))
                        case .swiftbuild:
                            #expect(stdout.contains("artifact-path:"))
                            #expect(stdout.contains(RelativePath("MyExecutable").pathString))
                        case .xcode:
                            Issue.record("unimplemented assertion for --build-system xcode")
                        }
                        #expect(stdout.contains("artifact-kind:"))
                        #expect(stdout.contains("executable"))
                    }

                    // Invoke the plugin with parameters choosing a concise build of MyExecutable for release.
                    do {
                        let (stdout, _) = try await execute(
                            ["my-build-tester", "--product", "MyExecutable", "--release"],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("Building for production..."))
                        #expect(!stdout.contains("-module-name MyExecutable"))
                        if buildSystemProvider == .native {
                            #expect(stdout.contains("Build of product 'MyExecutable' complete!"))
                        }
                        #expect(stdout.contains("succeeded: true"))
                        switch buildSystemProvider {
                        case .native:
                            #expect(stdout.contains("artifact-path:"))
                            #expect(stdout.contains(RelativePath("release/MyExecutable").pathString))
                        case .swiftbuild:
                            #expect(stdout.contains("artifact-path:"))
                            #expect(stdout.contains(RelativePath("MyExecutable").pathString))
                        case .xcode:
                            Issue.record("unimplemented assertion for --build-system xcode")
                        }
                        #expect(stdout.contains("artifact-kind:"))
                        #expect(stdout.contains("executable"))
                    }

                    // SwiftBuild is currently not producing a static archive for static products unless they are linked into some other binary.
                    try await withKnownIssue {
                        // Invoke the plugin with parameters choosing a verbose build of MyStaticLibrary for release.
                        do {
                            let (stdout, _) = try await execute(
                                ["my-build-tester", "--product", "MyStaticLibrary", "--print-commands", "--release"],
                                packagePath: packageDir,
                                configuration: data.config,
                                buildSystem: data.buildSystem,
                            )
                            #expect(stdout.contains("Building for production..."))
                            #expect(!stdout.contains("Building for debug..."))
                            #expect(!stdout.contains("-module-name MyLibrary"))
                            if buildSystemProvider == .native {
                                #expect(stdout.contains("Build of product 'MyStaticLibrary' complete!"))
                            }
                            #expect(stdout.contains("succeeded: true"))
                            switch buildSystemProvider {
                            case .native:
                                #expect(stdout.contains("artifact-path:"))
                                #expect(stdout.contains(RelativePath("release/libMyStaticLibrary").pathString))
                            case .swiftbuild:
                                #expect(stdout.contains("artifact-path:"))
                                #expect(stdout.contains(RelativePath("MyStaticLibrary").pathString))
                            case .xcode:
                                Issue.record("unimplemented assertion for --build-system xcode")
                            }
                            #expect(stdout.contains("artifact-kind:"))
                            #expect(stdout.contains("staticLibrary"))
                        }
                    } when: {
                        data.buildSystem == .swiftbuild
                    }

                    // Invoke the plugin with parameters choosing a verbose build of MyDynamicLibrary for release.
                    do {
                        let (stdout, _) = try await execute(
                            [
                                "my-build-tester", "--product", "MyDynamicLibrary", "--print-commands", "--release",
                            ],
                            packagePath: packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        #expect(stdout.contains("Building for production..."))
                        #expect(!stdout.contains("Building for debug..."))
                        #expect(!stdout.contains("-module-name MyLibrary"))
                        if buildSystemProvider == .native {
                            #expect(stdout.contains("Build of product 'MyDynamicLibrary' complete!"))
                        }
                        #expect(stdout.contains("succeeded: true"))
                        switch buildSystemProvider {
                        case .native:
                            #if os(Windows)
                                #expect(stdout.contains("artifact-path:"))
                                #expect(stdout.contains(RelativePath("release/MyDynamicLibrary.dll").pathString))
                            #else
                                #expect(stdout.contains("artifact-path:"))
                                #expect(stdout.contains(RelativePath("release/libMyDynamicLibrary").pathString))
                            #endif
                        case .swiftbuild:
                            #expect(stdout.contains("artifact-path:"))
                            #expect(stdout.contains(RelativePath("MyDynamicLibrary").pathString))
                        case .xcode:
                            Issue.record("unimplemented assertion for --build-system xcode")
                        }
                        #expect(stdout.contains("artifact-kind:"))
                        #expect(stdout.contains("dynamicLibrary"))
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
            }
        }

        @Test(
            .IssueWindowsRelativePathAssert,
            arguments: [BuildSystemProvider.Kind.native, .swiftbuild],
        )
        func commandPluginBuildingCallbacksExcludeUnbuiltArtifacts(buildSystem: BuildSystemProvider.Kind) async throws {
            try await withKnownIssue {
                try await fixture(name: "PartiallyUnusedDependency") { fixturePath in
                    let (stdout, _) = try await execute(
                        ["dump-artifacts-plugin"],
                        packagePath: fixturePath,
                        configuration: .debug,
                        buildSystem: buildSystem
                    )
                    // The build should succeed
                    #expect(stdout.contains("succeeded: true"))
                    // The artifacts corresponding to the executable and dylib we built should be reported
                    #expect(stdout.contains(#/artifact-path: [^\n]+MyExecutable(.*)?\nartifact-kind: executable/#))
                    #expect(stdout.contains(#/artifact-path: [^\n]+MyDynamicLibrary(.*)?\nartifact-kind: dynamicLibrary/#))
                    // The not-built executable in the dependency should not be reported. The native build system fails to exclude it.
                    withKnownIssue {
                        #expect(!stdout.contains("MySupportExecutable"))
                    } when: {
                        buildSystem == .native
                    }
                }
            } when: {
                buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .IssueWindowsRelativePathAssert,
            .requiresSwiftConcurrencySupport,
            // Depending on how the test is running, the `llvm-profdata` and `llvm-cov` tool might be unavailable.
            .requiresLLVMProfData,
            .requiresLLVMCov,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginTestingCallbacks(
            data: BuildData,
        ) async throws {
            try await withKnownIssue {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a library, a command plugin, and a couple of tests.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.createDirectory(packageDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string: """
                            // swift-tools-version: 5.6
                            import PackageDescription
                            let package = Package(
                                name: "MyPackage",
                                targets: [
                                    .target(
                                        name: "MyLibrary"
                                    ),
                                    .plugin(
                                        name: "MyPlugin",
                                        capability: .command(
                                            intent: .custom(verb: "my-test-tester", description: "Help description")
                                        )
                                    ),
                                    .testTarget(
                                        name: "MyBasicTests"
                                    ),
                                    .testTarget(
                                        name: "MyExtendedTests"
                                    ),
                                ]
                            )
                            """
                    )
                    let myPluginTargetDir = packageDir.appending(components: "Plugins", "MyPlugin")
                    try localFileSystem.createDirectory(myPluginTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myPluginTargetDir.appending("plugin.swift"),
                        string: """
                            import PackagePlugin
                            @main
                            struct MyCommandPlugin: CommandPlugin {
                                func performCommand(
                                    context: PluginContext,
                                    arguments: [String]
                                ) throws {
                                    do {
                                        let result = try packageManager.test(.filtered(["MyBasicTests"]), parameters: .init(enableCodeCoverage: true))
                                        assert(result.succeeded == true)
                                        assert(result.testTargets.count == 1)
                                        assert(result.testTargets[0].name == "MyBasicTests")
                                        assert(result.testTargets[0].testCases.count == 2)
                                        assert(result.testTargets[0].testCases[0].name == "MyBasicTests.TestSuite1")
                                        assert(result.testTargets[0].testCases[0].tests.count == 2)
                                        assert(result.testTargets[0].testCases[0].tests[0].name == "testBooleanInvariants")
                                        assert(result.testTargets[0].testCases[0].tests[1].result == .succeeded)
                                        assert(result.testTargets[0].testCases[0].tests[1].name == "testNumericalInvariants")
                                        assert(result.testTargets[0].testCases[0].tests[1].result == .succeeded)
                                        assert(result.testTargets[0].testCases[1].name == "MyBasicTests.TestSuite2")
                                        assert(result.testTargets[0].testCases[1].tests.count == 1)
                                        assert(result.testTargets[0].testCases[1].tests[0].name == "testStringInvariants")
                                        assert(result.testTargets[0].testCases[1].tests[0].result == .succeeded)
                                        assert(result.codeCoverageDataFile?.extension == "json")
                                    }
                                    catch {
                                        print("error from the plugin host: \\(error)")
                                    }
                                }
                            }
                            """
                    )
                    let myLibraryTargetDir = packageDir.appending(components: "Sources", "MyLibrary")
                    try localFileSystem.createDirectory(myLibraryTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myLibraryTargetDir.appending("library.swift"),
                        string: """
                            public func Foo() { }
                            """
                    )
                    let myBasicTestsTargetDir = packageDir.appending(components: "Tests", "MyBasicTests")
                    try localFileSystem.createDirectory(myBasicTestsTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myBasicTestsTargetDir.appending("Test1.swift"),
                        string: """
                            import XCTest
                            class TestSuite1: XCTestCase {
                                func testBooleanInvariants() throws {
                                    XCTAssertEqual(true || true, true)
                                }
                                func testNumericalInvariants() throws {
                                    XCTAssertEqual(1 + 1, 2)
                                }
                            }
                            """
                    )
                    try localFileSystem.writeFileContents(
                        myBasicTestsTargetDir.appending("Test2.swift"),
                        string: """
                            import XCTest
                            class TestSuite2: XCTestCase {
                                func testStringInvariants() throws {
                                    XCTAssertEqual("" + "", "")
                                }
                            }
                            """
                    )
                    let myExtendedTestsTargetDir = packageDir.appending(
                        components: "Tests",
                        "MyExtendedTests"
                    )
                    try localFileSystem.createDirectory(myExtendedTestsTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        myExtendedTestsTargetDir.appending("Test3.swift"),
                        string: """
                            import XCTest
                            class TestSuite3: XCTestCase {
                                func testArrayInvariants() throws {
                                    XCTAssertEqual([] + [], [])
                                }
                                func testImpossibilities() throws {
                                    XCTFail("no can do")
                                }
                            }
                            """
                    )

                    // Check basic usage with filtering and code coverage. The plugin itself asserts a bunch of values.
                    try await execute(
                        ["my-test-tester"],
                        packagePath: packageDir,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )

                    // We'll add checks for various error conditions here in a future commit.
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
            }
        }

        struct PluginAPIsData {
            let commandArgs: CLIArguments
            let expectedStdout: [String]
            let expectedStderr: [String]
        }

        @Test(
            .IssueWindowsPathLastComponent,
            // Only run the test if the environment in which we're running actually supports Swift concurrency (which the plugin APIs require).
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.Plugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                PluginAPIsData(
                    // Check that a target doesn't include itself in its recursive dependencies.
                    commandArgs: ["print-target-dependencies", "--target", "SecondTarget"],
                    expectedStdout: [
                        "Recursive dependencies of 'SecondTarget': [\"FirstTarget\"]",
                        "Module kind of 'SecondTarget': generic",
                    ],
                    expectedStderr: [],
                ),
                PluginAPIsData(
                    // Check that targets are not included twice in recursive dependencies.
                    commandArgs: ["print-target-dependencies", "--target", "ThirdTarget"],
                    expectedStdout: [
                        "Recursive dependencies of 'ThirdTarget': [\"FirstTarget\"]",
                        "Module kind of 'ThirdTarget': generic",
                    ],
                    expectedStderr: [],
                ),
                PluginAPIsData(
                    // Check that product dependencies work in recursive dependencies.
                    commandArgs: ["print-target-dependencies", "--target", "FourthTarget"],
                    expectedStdout: [
                        "Recursive dependencies of 'FourthTarget': [\"FirstTarget\", \"SecondTarget\", \"ThirdTarget\", \"HelperLibrary\"]",
                        "Module kind of 'FourthTarget': generic",
                    ],
                    expectedStderr: [],
                ),
                PluginAPIsData(
                    // Check some of the other utility APIs.
                    commandArgs: ["print-target-dependencies", "--target", "FifthTarget"],
                    expectedStdout: [
                        "execProducts: [\"FifthTarget\"]",
                        "swiftTargets: [\"FifthTarget\", \"FirstTarget\", \"FourthTarget\", \"SecondTarget\", \"TestTarget\", \"ThirdTarget\"]",
                        "swiftSources: [\"library.swift\", \"library.swift\", \"library.swift\", \"library.swift\", \"main.swift\", \"tests.swift\"]",
                        "Module kind of 'FifthTarget': executable",
                    ],
                    expectedStderr: [],
                ),
                PluginAPIsData(
                    // Check a test target.
                    commandArgs: ["print-target-dependencies", "--target", "TestTarget"],
                    expectedStdout: [
                        "Recursive dependencies of 'TestTarget': [\"FirstTarget\", \"SecondTarget\"]",
                        "Module kind of 'TestTarget': test",
                    ],
                    expectedStderr: [],
                ),
            ],
        )
        func pluginAPIs(
            buildData: BuildData,
            testData: PluginAPIsData
        ) async throws {
            try await withKnownIssue(isIntermittent: true) {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a plugin to test various parts of the API.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.createDirectory(packageDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        packageDir.appending("Package.swift"),
                        string: """
                                // swift-tools-version: 5.9
                                import PackageDescription
                                let package = Package(
                                    name: "MyPackage",
                                    dependencies: [
                                        .package(name: "HelperPackage", path: "VendoredDependencies/HelperPackage")
                                    ],
                                    targets: [
                                        .target(
                                            name: "FirstTarget",
                                            dependencies: [
                                            ]
                                        ),
                                        .target(
                                            name: "SecondTarget",
                                            dependencies: [
                                                "FirstTarget",
                                            ]
                                        ),
                                        .target(
                                            name: "ThirdTarget",
                                            dependencies: [
                                                "FirstTarget",
                                            ]
                                        ),
                                        .target(
                                            name: "FourthTarget",
                                            dependencies: [
                                                "SecondTarget",
                                                "ThirdTarget",
                                                .product(name: "HelperLibrary", package: "HelperPackage"),
                                            ]
                                        ),
                                        .executableTarget(
                                            name: "FifthTarget",
                                            dependencies: [
                                                "FirstTarget",
                                                "ThirdTarget",
                                            ]
                                        ),
                                        .testTarget(
                                            name: "TestTarget",
                                            dependencies: [
                                                "SecondTarget",
                                            ]
                                        ),
                                        .plugin(
                                            name: "PrintTargetDependencies",
                                            capability: .command(
                                                intent: .custom(verb: "print-target-dependencies", description: "Plugin that prints target dependencies; argument is name of target")
                                            )
                                        ),
                                    ]
                                )
                            """
                    )

                    let firstTargetDir = packageDir.appending(components: "Sources", "FirstTarget")
                    try localFileSystem.createDirectory(firstTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        firstTargetDir.appending("library.swift"),
                        string: """
                            public func FirstFunc() { }
                            """
                    )

                    let secondTargetDir = packageDir.appending(components: "Sources", "SecondTarget")
                    try localFileSystem.createDirectory(secondTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        secondTargetDir.appending("library.swift"),
                        string: """
                            public func SecondFunc() { }
                            """
                    )

                    let thirdTargetDir = packageDir.appending(components: "Sources", "ThirdTarget")
                    try localFileSystem.createDirectory(thirdTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        thirdTargetDir.appending("library.swift"),
                        string: """
                            public func ThirdFunc() { }
                            """
                    )

                    let fourthTargetDir = packageDir.appending(components: "Sources", "FourthTarget")
                    try localFileSystem.createDirectory(fourthTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        fourthTargetDir.appending("library.swift"),
                        string: """
                            public func FourthFunc() { }
                            """
                    )

                    let fifthTargetDir = packageDir.appending(components: "Sources", "FifthTarget")
                    try localFileSystem.createDirectory(fifthTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        fifthTargetDir.appending("main.swift"),
                        string: """
                            @main struct MyExec {
                                func run() throws {}
                            }
                            """
                    )

                    let testTargetDir = packageDir.appending(components: "Tests", "TestTarget")
                    try localFileSystem.createDirectory(testTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        testTargetDir.appending("tests.swift"),
                        string: """
                            import XCTest
                            class MyTestCase: XCTestCase {
                            }
                            """
                    )

                    let pluginTargetTargetDir = packageDir.appending(
                        components: "Plugins",
                        "PrintTargetDependencies"
                    )
                    try localFileSystem.createDirectory(pluginTargetTargetDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        pluginTargetTargetDir.appending("plugin.swift"),
                        string: """
                            import PackagePlugin
                            @main struct PrintTargetDependencies: CommandPlugin {
                                func performCommand(
                                    context: PluginContext,
                                    arguments: [String]
                                ) throws {
                                    // Print names of the recursive dependencies of the given target.
                                    var argExtractor = ArgumentExtractor(arguments)
                                    guard let targetName = argExtractor.extractOption(named: "target").first else {
                                        throw "No target argument provided"
                                    }
                                    guard let target = try? context.package.targets(named: [targetName]).first else {
                                        throw "No target found with the name '\\(targetName)'"
                                    }
                                    print("Recursive dependencies of '\\(target.name)': \\(target.recursiveTargetDependencies.map(\\.name))")

                                    let execProducts = context.package.products(ofType: ExecutableProduct.self)
                                    print("execProducts: \\(execProducts.map{ $0.name })")
                                    let swiftTargets = context.package.targets(ofType: SwiftSourceModuleTarget.self)
                                    print("swiftTargets: \\(swiftTargets.map{ $0.name }.sorted())")
                                    let swiftSources = swiftTargets.flatMap{ $0.sourceFiles(withSuffix: ".swift") }
                                    print("swiftSources: \\(swiftSources.map{ $0.path.lastComponent }.sorted())")

                                    if let target = target.sourceModule {
                                        print("Module kind of '\\(target.name)': \\(target.kind)")
                                    }

                                    var sourceModules = context.package.sourceModules
                                    print("sourceModules in package: \\(sourceModules.map { $0.name })")
                                    sourceModules = context.package.products.first?.sourceModules ?? []
                                    print("sourceModules in first product: \\(sourceModules.map { $0.name })")
                                }
                            }
                            extension String: Error {}
                            """
                    )

                    // Create a separate vendored package so that we can test dependencies across products in other packages.
                    let helperPackageDir = packageDir.appending(
                        components: "VendoredDependencies",
                        "HelperPackage"
                    )
                    try localFileSystem.createDirectory(helperPackageDir, recursive: true)
                    try localFileSystem.writeFileContents(
                        helperPackageDir.appending("Package.swift"),
                        string: """
                            // swift-tools-version: 5.6
                            import PackageDescription
                            let package = Package(
                                name: "HelperPackage",
                                products: [
                                    .library(
                                        name: "HelperLibrary",
                                        targets: ["HelperLibrary"])
                                ],
                                targets: [
                                    .target(
                                        name: "HelperLibrary",
                                        path: ".")
                                ]
                            )
                            """
                    )
                    try localFileSystem.writeFileContents(
                        helperPackageDir.appending("library.swift"),
                        string: """
                            public func Foo() { }
                            """
                    )

                    let (stdout, stderr) = try await execute(
                        testData.commandArgs,
                        packagePath: packageDir,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    for expected in testData.expectedStdout {
                        #expect(stdout.contains(expected))
                    }
                    for expected in testData.expectedStderr {
                        #expect(stderr.contains(expected))
                    }
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .IssueWindowsLongPath,
            .tags(
                .Feature.Command.Package.Plugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func pluginCompilationBeforeBuilding(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a couple of plugins a other targets and products.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.createDirectory(packageDir, recursive: true)
                try localFileSystem.writeFileContents(
                    packageDir.appending(components: "Package.swift"),
                    string: """
                        // swift-tools-version: 5.6
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            products: [
                                .library(
                                    name: "MyLibrary",
                                    targets: ["MyLibrary"]
                                ),
                                .executable(
                                    name: "MyExecutable",
                                    targets: ["MyExecutable"]
                                ),
                            ],
                            targets: [
                                .target(
                                    name: "MyLibrary"
                                ),
                                .executableTarget(
                                    name: "MyExecutable",
                                    dependencies: ["MyLibrary"]
                                ),
                                .plugin(
                                    name: "MyBuildToolPlugin",
                                    capability: .buildTool()
                                ),
                                .plugin(
                                    name: "MyCommandPlugin",
                                    capability: .command(
                                        intent: .custom(verb: "my-build-tester", description: "Help description")
                                    )
                                ),
                            ]
                        )
                        """
                )
                let myLibraryTargetDir = packageDir.appending(components: "Sources", "MyLibrary")
                try localFileSystem.createDirectory(myLibraryTargetDir, recursive: true)
                try localFileSystem.writeFileContents(
                    myLibraryTargetDir.appending("library.swift"),
                    string: """
                        public func GetGreeting() -> String { return "Hello" }
                        """
                )
                let myExecutableTargetDir = packageDir.appending(components: "Sources", "MyExecutable")
                try localFileSystem.createDirectory(myExecutableTargetDir, recursive: true)
                try localFileSystem.writeFileContents(
                    myExecutableTargetDir.appending("main.swift"),
                    string: """
                        import MyLibrary
                        print("\\(GetGreeting()), World!")
                        """
                )
                let myBuildToolPluginTargetDir = packageDir.appending(
                    components: "Plugins",
                    "MyBuildToolPlugin"
                )
                try localFileSystem.createDirectory(myBuildToolPluginTargetDir, recursive: true)
                try localFileSystem.writeFileContents(
                    myBuildToolPluginTargetDir.appending("plugin.swift"),
                    string: """
                        import PackagePlugin
                        @main struct MyBuildToolPlugin: BuildToolPlugin {
                            func createBuildCommands(
                                context: PluginContext,
                                target: Target
                            ) throws -> [Command] {
                                return []
                            }
                        }
                        """
                )
                let myCommandPluginTargetDir = packageDir.appending(
                    components: "Plugins",
                    "MyCommandPlugin"
                )
                try localFileSystem.createDirectory(myCommandPluginTargetDir, recursive: true)
                try localFileSystem.writeFileContents(
                    myCommandPluginTargetDir.appending("plugin.swift"),
                    string: """
                        import PackagePlugin
                        @main struct MyCommandPlugin: CommandPlugin {
                            func performCommand(
                                context: PluginContext,
                                arguments: [String]
                            ) throws {
                            }
                        }
                        """
                )

                // Check that building without options compiles both plugins and that the build proceeds.
                try await withKnownIssue(isIntermittent: true) {
                    do {
                        let (stdout, _) = try await executeSwiftBuild(
                            packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                        if data.buildSystem == .native {
                            #expect(stdout.contains("Compiling plugin MyBuildToolPlugin"))
                            #expect(stdout.contains("Compiling plugin MyCommandPlugin"))
                        }
                        #expect(stdout.contains("Building for \(data.config.buildFor)..."))
                    }
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
                }

                // Check that building just one of them just compiles that plugin and doesn't build anything else.
                do {
                    let (stdout, stderr) = try await executeSwiftBuild(
                        packageDir,
                        configuration: data.config,
                        extraArgs: ["--target", "MyCommandPlugin"],
                        buildSystem: data.buildSystem,
                    )
                    switch data.buildSystem {
                    case .native:
                            #expect(!stdout.contains("Compiling plugin MyBuildToolPlugin"), "stderr: \(stderr)")
                            #expect(stdout.contains("Compiling plugin MyCommandPlugin"), "stderr: \(stderr)")
                        case .swiftbuild:
                        // nothing specific
                        break
                        case .xcode:
                            Issue.record("Test expected have not been considered")
                    }
                    #expect(!stdout.contains("Building for \(data.config.buildFor)..."), "stderr: \(stderr)")
                }
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.CommandPlugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func commandPluginCompilationErrorImplementation(
            data: BuildData,
        ) async throws {
            try await fixture(name: "Miscellaneous/Plugins/CommandPluginCompilationError") { packageDir in
                // Check that building stops after compiling the plugin and doesn't proceed.
                // Run this test a number of times to try to catch any race conditions.
                for num in 1...5 {
                    await expectThrowsCommandExecutionError(
                        try await executeSwiftBuild(
                            packageDir,
                            configuration: data.config,
                            buildSystem: data.buildSystem,
                        )
                    ) { error in
                        let stdout = error.stdout
                        let stderr = error.stderr
                        withKnownIssue(isIntermittent: true) {
                            #expect(
                                stdout.contains(
                                    "error: consecutive statements on a line must be separated by ';'"
                                ),
                                "iteration \(num) failed.  stderr: \(stderr)",
                            )
                        } when: {
                            data.buildSystem == .native
                        }
                        #expect(
                            !stdout.contains("Building for \(data.config.buildFor)..."),
                            "iteration \(num) failed.   stderr: \(stderr)",
                        )
                    }
                }
            }
        }

        @Test(
            .requiresSwiftConcurrencySupport,
            .tags(
                .Feature.Command.Package.Plugin,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func singlePluginTarget(
            data: BuildData,
        ) async throws {
            try await testWithTemporaryDirectory { tmpPath in
                // Create a sample package with a library target and a plugin.
                let packageDir = tmpPath.appending(components: "MyPackage")
                try localFileSystem.createDirectory(packageDir, recursive: true)
                try localFileSystem.writeFileContents(
                    packageDir.appending("Package.swift"),
                    string: """
                        // swift-tools-version: 5.7
                        import PackageDescription
                        let package = Package(
                            name: "MyPackage",
                            products: [
                                .plugin(name: "Foo", targets: ["Foo"])
                            ],
                            dependencies: [
                            ],
                            targets: [
                                .plugin(
                                    name: "Foo",
                                    capability: .command(
                                        intent: .custom(verb: "Foo", description: "Plugin example"),
                                        permissions: []
                                    )
                                )
                            ]
                        )
                        """
                )

                let myPluginTargetDir = packageDir.appending(components: "Plugins", "Foo")
                try localFileSystem.createDirectory(myPluginTargetDir, recursive: true)
                try localFileSystem.writeFileContents(
                    myPluginTargetDir.appending("plugin.swift"),
                    string: """
                        import PackagePlugin
                        @main struct FooPlugin: BuildToolPlugin {
                            func createBuildCommands(
                                context: PluginContext,
                                target: Target
                            ) throws -> [Command] { }
                        }
                        """
                )

                // Load a workspace from the package.
                let observability = ObservabilitySystem.makeForTesting()
                let workspace = try Workspace(
                    fileSystem: localFileSystem,
                    forRootPackage: packageDir,
                    customManifestLoader: ManifestLoader(toolchain: UserToolchain.default),
                    delegate: MockWorkspaceDelegate()
                )

                // Load the root manifest.
                let rootInput = PackageGraphRootInput(packages: [packageDir], dependencies: [])
                let rootManifests = try await workspace.loadRootManifests(
                    packages: rootInput.packages,
                    observabilityScope: observability.topScope
                )
                #expect(rootManifests.count == 1, "Root manifest: \(rootManifests)")

                // Load the package graph.
                let _ = try await workspace.loadPackageGraph(
                    rootInput: rootInput,
                    observabilityScope: observability.topScope
                )
                expectNoDiagnostics(observability.diagnostics)
            }
        }

        @Test(arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms))
        func commandPluginDynamicDependencies(
            buildData: BuildData
        ) async throws {
            try await withKnownIssue {
                try await testWithTemporaryDirectory { tmpPath in
                    // Create a sample package with a command plugin that has a dynamic dependency.
                    let packageDir = tmpPath.appending(components: "MyPackage")
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Package.swift"),
                        string:
                            """
                            // swift-tools-version: 6.0
                            // The swift-tools-version declares the minimum version of Swift required to build this package.

                            import PackageDescription

                            let package = Package(
                                name: "command-plugin-dynamic-linking",
                                products: [
                                    // Products can be used to vend plugins, making them visible to other packages.
                                    .plugin(
                                        name: "command-plugin-dynamic-linking",
                                        targets: ["command-plugin-dynamic-linking"]),
                                ],
                                dependencies: [
                                    .package(path: "LocalPackages/DynamicLib")
                                ],
                                targets: [
                                    // Targets are the basic building blocks of a package, defining a module or a test suite.
                                    // Targets can depend on other targets in this package and products from dependencies.
                                    .executableTarget(
                                        name: "Core",
                                        dependencies: [
                                            .product(name: "DynamicLib", package: "DynamicLib")
                                        ]
                                    ),
                                    .plugin(
                                        name: "command-plugin-dynamic-linking",
                                        capability: .command(intent: .custom(
                                            verb: "command_plugin_dynamic_linking",
                                            description: "prints hello world"
                                        )),
                                        dependencies: [
                                            "Core"
                                        ]
                                    )
                                ]
                            )
                            """
                    )
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Sources", "Core", "Core.swift"),
                        string:
                            """
                            import DynamicLib

                            @main
                            struct Core {
                                static func main() {
                                    let result = dynamicLibFunc()
                                    print(result)
                                }
                            }
                            """
                    )
                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "Plugins", "command-plugin-dynamic-linking.swift"),
                        string:
                            """
                            import PackagePlugin
                            import Foundation

                            enum CommandError: Error, CustomStringConvertible {
                                var description: String {
                                    String(describing: self)
                                }

                                case pluginError(String)
                            }

                            @main
                            struct command_plugin_dynamic_linking: CommandPlugin {
                                // Entry point for command plugins applied to Swift Packages.
                                func performCommand(context: PluginContext, arguments: [String]) async throws {
                                    let tool = try context.tool(named: "Core")

                                    let process = try Process.run(tool.url, arguments: arguments)
                                    process.waitUntilExit()

                                    if process.terminationReason != .exit || process.terminationStatus != 0 {
                                        throw CommandError.pluginError("\\(tool.name) failed")
                                    } else {
                                        print("Works fine!")
                                    }
                                }
                            }

                            #if canImport(XcodeProjectPlugin)
                            import XcodeProjectPlugin

                            extension command_plugin_dynamic_linking: XcodeCommandPlugin {
                                // Entry point for command plugins applied to Xcode projects.
                                func performCommand(context: XcodePluginContext, arguments: [String]) throws {
                                    print("Hello, World!")
                                }
                            }

                            #endif
                            """
                    )

                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "LocalPackages", "DynamicLib", "Package.swift"),
                        string:
                            """
                            // swift-tools-version: 6.0
                            // The swift-tools-version declares the minimum version of Swift required to build this package.

                            import PackageDescription

                            let package = Package(
                                name: "DynamicLib",
                                products: [
                                    // Products define the executables and libraries a package produces, making them visible to other packages.
                                    .library(
                                        name: "DynamicLib",
                                        type: .dynamic,
                                        targets: ["DynamicLib"]),
                                ],
                                targets: [
                                    // Targets are the basic building blocks of a package, defining a module or a test suite.
                                    // Targets can depend on other targets in this package and products from dependencies.
                                    .target(
                                        name: "DynamicLib"),
                                    .testTarget(
                                        name: "DynamicLibTests",
                                        dependencies: ["DynamicLib"]
                                    ),
                                ]
                            )
                            """
                    )

                    try localFileSystem.writeFileContents(
                        packageDir.appending(components: "LocalPackages", "DynamicLib", "Sources", "DynamicLib.swift"),
                        string:
                            """
                            // The Swift Programming Language
                            // https://docs.swift.org/swift-book

                            public func dynamicLibFunc() -> String {
                                return "Hello from DynamicLib!"
                            }
                            """
                    )

                    let (stdout, _) = try await execute(
                        ["plugin", "command_plugin_dynamic_linking"],
                        packagePath: packageDir,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )

                    #expect(stdout.contains("Works fine!"))
                }
            } when: {
                (ProcessInfo.hostOperatingSystem == .windows && buildData.buildSystem == .swiftbuild) || (ProcessInfo.hostOperatingSystem == .linux && buildData.buildSystem == .swiftbuild)
            }
        }
    }
}
