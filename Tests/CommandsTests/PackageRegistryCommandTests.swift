//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Commands
import Foundation
import PackageLoading
import PackageModel
import PackageRegistry
@testable import PackageRegistryCommand
import struct SPMBuildCore.BuildSystemProvider
import PackageSigning
import _InternalTestSupport
import TSCclibc // for SPM_posix_spawn_file_actions_addchdir_np_supported
import Workspace
import Testing

import enum TSCBasic.JSON
import struct Basics.AsyncProcessResult

let defaultRegistryBaseURL = URL("https://packages.example.com")
let customRegistryBaseURL = URL("https://custom.packages.example.com")

struct PackageRegistryCommandTests {
    @discardableResult
    private func execute(
        _ args: [String],
        configuration: BuildConfiguration,
        packagePath: AbsolutePath? = nil,
        env: Environment? = nil,
        buildSystem: BuildSystemProvider.Kind,
    ) async throws -> (stdout: String, stderr: String) {
        var environment = env ?? [:]
        // don't ignore local packages when caching
        environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
        return try await executeSwiftPackageRegistry(
            packagePath,
            configuration: configuration,
            extraArgs: args,
            env: environment,
            buildSystem: buildSystem,
        )
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.General,
        ),
        .requiresSwiftConcurrencySupport,
    )
    func usage() async throws {
        let stdout = try await SwiftPM.Registry.execute(["-help"]).stdout
        #expect(stdout.contains("USAGE: swift package-registry"), "got stdout: '\(stdout)'")
    }


    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.General,
        ),
        .requiresSwiftConcurrencySupport,
    )
    func seeAlso() async throws {
        let stdout = try await SwiftPM.Registry.execute(["--help"]).stdout
        #expect(stdout.contains("SEE ALSO: swift package"), "got stdout: '\(stdout)'")
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.General,
        ),
    )
    func commandDoesNotEmitDuplicateSymbols() async throws {
        let (stdout, stderr) = try await SwiftPM.Registry.execute(["--help"])
        let duplicateSymbolRegex = try #require(duplicateSymbolRegex)
        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.General,
        ),
        .requiresSwiftConcurrencySupport,
    )
    func version() async throws {
        let stdout = try await SwiftPM.Registry.execute(["--version"]).stdout
        let versionRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(versionRegex))
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
            .Feature.Command.PackageRegistry.Unset,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func localConfiguration(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                try await execute(
                    ["set", "\(defaultRegistryBaseURL)"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string == "\(defaultRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Set new default registry
            do {
                try await execute(
                    ["set", "\(customRegistryBaseURL)"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Set default registry with allow-insecure-http option
            do {
                try await execute(
                    ["set", "\(customRegistryBaseURL)", "--allow-insecure-http"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Unset default registry
            do {
                try await execute(
                    ["unset"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 0)
                #expect(json["version"] == .int(1))
            }

            // Set registry for "foo" scope
            do {
                try await execute(
                    ["set", "\(customRegistryBaseURL)", "--scope", "foo"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["foo"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Set registry for "bar" scope
            do {
                try await execute(
                    ["set", "\(customRegistryBaseURL)", "--scope", "bar"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 2)
                #expect(json["registries"]?.dictionary?["foo"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["registries"]?.dictionary?["bar"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Unset registry for "foo" scope
            do {
                try await execute(
                    ["unset", "--scope", "foo"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["bar"]?.dictionary?["url"]?.string == "\(customRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            #expect(localFileSystem.exists(configurationFilePath))
        }
    }

    // TODO: Test global configuration

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func setMissingURL(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            await #expect(throws: (any Error).self) {
                try await execute(
                    ["set", "--scope", "foo"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )
            }

            #expect(!localFileSystem.exists(configurationFilePath))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func setInvalidURL(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            await #expect(throws: (any Error).self) {
                try await execute(
                    ["set", "invalid"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )
            }

            #expect(!localFileSystem.exists(configurationFilePath))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func setInsecureURL(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            await #expect(throws: (any Error).self) {
                try await execute(
                    ["set", "http://package.example.com"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )
            }

            #expect(!localFileSystem.exists(configurationFilePath))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func setAllowedInsecureURL(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            try await execute(
                ["set", "http://package.example.com", "--allow-insecure-http"],
                configuration: config,
                packagePath: packageRoot,
                buildSystem: buildSystem,
            )

            #expect(localFileSystem.exists(configurationFilePath))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func setInvalidScope(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                await #expect(throws: (any Error).self) {
                    try await execute(
                        ["set", "--scope", "_invalid_", "\(defaultRegistryBaseURL)"],
                        configuration: config,
                        packagePath: packageRoot,
                        buildSystem: buildSystem,
                    )
                }
            }

            #expect(!localFileSystem.exists(configurationFilePath))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Set,
            .Feature.Command.PackageRegistry.Unset,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func unsetMissingEntry(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageRoot
            )

            #expect(!localFileSystem.exists(configurationFilePath))

            // Set default registry
            do {
                try await execute(
                    ["set", "\(defaultRegistryBaseURL)"],
                    configuration: config,
                    packagePath: packageRoot,
                    buildSystem: buildSystem,
                )

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string == "\(defaultRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            // Unset registry for missing "baz" scope
            do {
                await #expect(throws: (any Error).self) {
                    try await execute(
                        ["unset", "--scope", "baz"],
                        configuration: config,
                        packagePath: packageRoot,
                        buildSystem: buildSystem,
                    )
                }

                let json = try JSON(data: localFileSystem.readFileContents(configurationFilePath))
                #expect(json["registries"]?.dictionary?.count == 1)
                #expect(json["registries"]?.dictionary?["[default]"]?.dictionary?["url"]?.string == "\(defaultRegistryBaseURL)")
                #expect(json["version"] == .int(1))
            }

            #expect(localFileSystem.exists(configurationFilePath))
        }
    }

    // TODO: Test example with login and password

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func archiving(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let packageIdentity = PackageIdentity.plain("org.package")
        let metadataFilename = PackageRegistryCommand.Publish.metadataFilename

        // git repo
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            initGitRepo(packageDirectory)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "1.3.5",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            try await validatePackageArchive(at: archivePath)
            #expect(archivePath.isDescendant(of: workingDirectory))
        }

        // not a git repo
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "1.5.4",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            try await validatePackageArchive(at: archivePath)
        }

        // canonical metadata location
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            // metadata file
            try localFileSystem.writeFileContents(
                packageDirectory.appending(component: metadataFilename),
                bytes: ""
            )

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "0.3.1",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let extractedPath = try await validatePackageArchive(at: archivePath)
            expectFileExists(at: extractedPath.appending(component: metadataFilename))
        }

        @discardableResult
        func validatePackageArchive(at archivePath: AbsolutePath) async throws -> AbsolutePath {
            expectFileExists(at: archivePath)
            let archiver = ZipArchiver(fileSystem: localFileSystem)
            let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractPath)
            try await archiver.extract(from: archivePath, to: extractPath)
            try localFileSystem.stripFirstLevel(of: extractPath)
            expectFileExists(at: extractPath.appending("Package.swift"))
            return extractPath
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Publish,
        ),
        .requiresWorkingDirectorySupport,
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func publishingToHTTPRegistry(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) throws {


        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "http://packages.example.com"

        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            await #expect(throws: (any Error).self) {
                try await executeSwiftPackageRegistry(
                    packageDirectory,
                    configuration: config,
                    extraArgs: [
                        "publish",
                        packageIdentity,
                        version,
                        "--url=\(registryURL)",
                        "--scratch-directory=\(workingDirectory.pathString)",
                        "--dry-run",
                    ],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Publish,
        ),
        .requiresWorkingDirectorySupport,
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func publishingToAllowedHTTPRegistry(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "http://packages.example.com"

        // with no authentication configured for registry
        _ = try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--allow-insecure-http",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )
        }

        // with authentication configured for registry
        _ = try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let configurationFilePath = AbsolutePath(
                ".swiftpm/configuration/registries.json",
                relativeTo: packageDirectory
            )

            try localFileSystem.createDirectory(configurationFilePath.parentDirectory, recursive: true)
            var configuration = RegistryConfiguration()
            try configuration.add(authentication: .init(type: .basic), for: URL(registryURL))
            try localFileSystem.writeFileContents(configurationFilePath, data: JSONEncoder().encode(configuration))

            await #expect(throws: (any Error).self) {
                try await executeSwiftPackageRegistry(
                    packageDirectory,
                    configuration: config,
                    extraArgs: [
                        "publish",
                        packageIdentity,
                        version,
                        "--url=\(registryURL)",
                        "--scratch-directory=\(workingDirectory.pathString)",
                        "--allow-insecure-http",
                        "--dry-run",
                    ],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    @Test(
        .requiresWorkingDirectorySupport,
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Publish,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func publishingUnsignedPackage(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) throws {
        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "https://packages.example.com"

        // custom metadata path
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = temporaryDirectory.appending("metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--metadata-path=\(metadataPath.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        // canonical metadata path
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = packageDirectory.appending(PackageRegistryCommand.Publish.metadataFilename)
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        // no metadata
        _ = try withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()
            expectFileExists(at: packageDirectory.appending("Package.swift"))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")

            // manifest should not be signed
            let manifest = try localFileSystem.readFileContents(packageDirectory.appending("Package.swift")).contents
            try await validateManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest
            )
        }

        @Sendable
        func validateManifest(
            manifestFile: String,
            in archivePath: AbsolutePath,
            manifestContent: [UInt8]
        ) async throws {
            expectFileExists(at: archivePath)
            let archiver = ZipArchiver(fileSystem: localFileSystem)
            let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractPath)
            try await archiver.extract(from: archivePath, to: extractPath)
            try localFileSystem.stripFirstLevel(of: extractPath)

            let manifestInArchive = try localFileSystem.readFileContents(extractPath.appending(manifestFile)).contents
            #expect(manifestInArchive == manifestContent)
        }
    }

    @Test(
        .requiresWorkingDirectorySupport,
        .requiresSwiftConcurrencySupport,
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Publish,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func publishingSignedPackage(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) async throws {
        let observabilityScope = ObservabilitySystem.makeForTesting().topScope

        let packageIdentity = "test.my-package"
        let version = "0.1.0"
        let registryURL = "https://packages.example.com"
        let signatureFormat = SignatureFormat.cms_1_0_0

        // custom metadata path
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            expectFileExists(at: manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = temporaryDirectory.appending("metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--metadata-path=\(metadataPath.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try getRoots()

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await self.validateSignature(
                signature: signature,
                content: archive,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // metadata signature
            let metadata = try localFileSystem.readFileContents(metadataPath).contents
            let metadataSignaturePath = workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig")
            let metadataSignature = try localFileSystem.readFileContents(metadataSignaturePath).contents
            try await self.validateSignature(
                signature: metadataSignature,
                content: metadata,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }

        // canonical metadata path
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            expectFileExists(at: manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let metadataPath = packageDirectory.appending(PackageRegistryCommand.Publish.metadataFilename)
            try localFileSystem.writeFileContents(metadataPath, string: "{}")

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try getRoots()

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await self.validateSignature(
                signature: signature,
                content: archive,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // metadata signature
            let metadata = try localFileSystem.readFileContents(metadataPath).contents
            let metadataSignaturePath = workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig")
            let metadataSignature = try localFileSystem.readFileContents(metadataSignaturePath).contents
            try await self.validateSignature(
                signature: metadataSignature,
                content: metadata,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }

        // no metadata
        try await withTemporaryDirectory { temporaryDirectory in
            let packageDirectory = temporaryDirectory.appending("MyPackage")
            try localFileSystem.createDirectory(packageDirectory)

            let initPackage = try InitPackage(
                name: "MyPackage",
                packageType: .executable,
                destinationPath: packageDirectory,
                fileSystem: localFileSystem
            )
            try initPackage.writePackageStructure()

            let manifestPath = packageDirectory.appending("Package.swift")
            expectFileExists(at: manifestPath)

            let versionSpecificManifestPath = packageDirectory.appending("Package@swift-\(ToolsVersion.current).swift")
            try localFileSystem.copy(from: manifestPath, to: versionSpecificManifestPath)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory)

            let certificatePath = temporaryDirectory.appending(component: "certificate.cer")
            let intermediateCertificatePath = temporaryDirectory.appending(component: "intermediate.cer")
            let privateKeyPath = temporaryDirectory.appending(component: "private-key.p8")

            try fixture(name: "Signing", createGitRepo: false) { fixturePath in
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec.cer"),
                    to: certificatePath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "Test_ec_key.p8"),
                    to: privateKeyPath
                )
                try localFileSystem.copy(
                    from: fixturePath.appending(components: "Certificates", "TestIntermediateCA.cer"),
                    to: intermediateCertificatePath
                )
            }

            try await executeSwiftPackageRegistry(
                packageDirectory,
                configuration: config,
                extraArgs: [
                    "publish",
                    packageIdentity,
                    version,
                    "--url=\(registryURL)",
                    "--scratch-directory=\(workingDirectory.pathString)",
                    "--private-key-path=\(privateKeyPath.pathString)",
                    "--cert-chain-paths=\(certificatePath.pathString)",
                    "\(intermediateCertificatePath.pathString)",
                    "--dry-run",
                ],
                buildSystem: buildSystem,
            )

            // Validate signatures
            var verifierConfiguration = VerifierConfiguration()
            verifierConfiguration.trustedRoots = try getRoots()

            // archive signature
            let archivePath = workingDirectory.appending("\(packageIdentity)-\(version).zip")
            let archive = try localFileSystem.readFileContents(archivePath).contents
            let signaturePath = workingDirectory.appending("\(packageIdentity)-\(version).sig")
            let signature = try localFileSystem.readFileContents(signaturePath).contents
            try await self.validateSignature(
                signature: signature,
                content: archive,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            // no metadata so no signature
            #expect(!localFileSystem
                .exists(workingDirectory.appending("\(packageIdentity)-\(version)-metadata.sig")))

            // manifest signatures
            let manifest = try localFileSystem.readFileContents(manifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package.swift",
                in: archivePath,
                manifestContent: manifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )

            let versionSpecificManifest = try localFileSystem.readFileContents(versionSpecificManifestPath).contents
            try await self.validateSignedManifest(
                manifestFile: "Package@swift-\(ToolsVersion.current).swift",
                in: archivePath,
                manifestContent: versionSpecificManifest,
                format: signatureFormat,
                verifierConfiguration: verifierConfiguration,
                observabilityScope: observabilityScope
            )
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Login,
        ),
    )
    func loginRequiresHTTPS() async {
        let registryURL = URL(string: "http://packages.example.com")!

        await #expect(throws: (any Error).self) {
            try await SwiftPM.Registry.execute(["login", "--url", registryURL.absoluteString])
        }
    }

    struct LogingUrlData {
        let loginApiPath: String?
        let expectedComponent: String
    }
    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Login,
        ),
        arguments: [
            LogingUrlData(loginApiPath: nil, expectedComponent: "login"),
            LogingUrlData(loginApiPath: "/secret-sign-in", expectedComponent: "secret-sign-in"),
        ], [
            "https://packages.example.com",
            // "https://packages.example.com:8081",
        ]
    )
    func createLoginURL(
        data: LogingUrlData,
        registryUrl: String,
    ) async throws {
        let registryURL = try #require(URL(string: registryUrl), "Failed to instantiate registry URL")

        let actualUrl =  try PackageRegistryCommand.Login.loginURL(from: registryURL, loginAPIPath: data.loginApiPath)
        let actualString =  actualUrl.absoluteString

        #expect(actualString == "\(registryUrl)/\(data.expectedComponent)")
    }

    @Test(
        .tags(
            .TestSize.small,
        ),
    )
    func validateRegistryURL() throws {

        try URL(string: "https://packages.example.com")!.validateRegistryURL()
        try URL(string: "https://packages.example.com")!.validateRegistryURL(allowHTTP: true)

        // Invalid
        #expect(throws: (any Error).self) {
            try URL(string: "http://packages.example.com")!.validateRegistryURL()
        }
        #expect(throws: (any Error).self) {
            try URL(string: "http://packages.example.com")!.validateRegistryURL(allowHTTP: false)
        }
        #expect(throws: (any Error).self) {
            try URL(string: "ssh://packages.example.com")!.validateRegistryURL()
        }
        #expect(throws: (any Error).self) {
            try URL(string: "ftp://packages.example.com")!.validateRegistryURL(allowHTTP: true)
        }
    }

    private func getRoots() throws -> [[UInt8]] {
        try fixture(name: "Signing", createGitRepo: false) { fixturePath in
            let rootCA = try localFileSystem
                .readFileContents(fixturePath.appending(components: "Certificates", "TestRootCA.cer")).contents
            return [rootCA]
        }
    }

    private func validateSignature(
        signature: [UInt8],
        content: [UInt8],
        format: SignatureFormat = .cms_1_0_0,
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws {
        let signatureStatus = try await SignatureProvider.status(
            signature: signature,
            content: content,
            format: format,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: observabilityScope
        )
        guard case .valid = signatureStatus else {
            Issue.record("Expected signature status to be .valid but got \(signatureStatus)")
            return
        }
    }

    private func validateSignedManifest(
        manifestFile: String,
        in archivePath: AbsolutePath,
        manifestContent: [UInt8],
        format: SignatureFormat = .cms_1_0_0,
        verifierConfiguration: VerifierConfiguration,
        observabilityScope: ObservabilityScope
    ) async throws {
        expectFileExists(at: archivePath)
        let archiver = ZipArchiver(fileSystem: localFileSystem)
        let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
        try localFileSystem.createDirectory(extractPath)
        try await archiver.extract(from: archivePath, to: extractPath)
        try localFileSystem.stripFirstLevel(of: extractPath)

        let manifestSignature = try ManifestSignatureParser.parse(
            manifestPath: extractPath.appending(manifestFile),
            fileSystem: localFileSystem
        )
        #expect(manifestSignature != nil)
        #expect(manifestSignature!.contents == manifestContent)
        let signature = manifestSignature!.signature
        try await self.validateSignature(
            signature: signature,
            content: manifestContent,
            format: format,
            verifierConfiguration: verifierConfiguration,
            observabilityScope: observabilityScope
        )
    }
}
