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
import SourceControl
import _InternalTestSupport
import TSCclibc // for SPM_posix_spawn_file_actions_addchdir_np_supported
import Workspace
import Testing

import enum TSCBasic.JSON
import struct Basics.AsyncProcessResult

let defaultRegistryBaseURL = URL("https://packages.example.com")
let customRegistryBaseURL = URL("https://custom.packages.example.com")

@Suite(
    .serializedIfOnWindows,
    .tags(
        .Feature.Command.PackageRegistry.General,
    ),
)
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func localConfiguration(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func setMissingURL(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func setInvalidURL(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func setInsecureURL(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func setAllowedInsecureURL(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func setInvalidScope(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func unsetMissingEntry(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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

    @discardableResult
    private static func validateCanonicalArchive(at archivePath: AbsolutePath) async throws -> AbsolutePath {
        expectFileExists(at: archivePath)
        let archiver = UniversalArchiver(localFileSystem)
        let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
        try localFileSystem.createDirectory(extractPath)
        try await archiver.extract(from: archivePath, to: extractPath)
        try localFileSystem.stripFirstLevel(of: extractPath)
        expectFileExists(at: extractPath.appending("Package.swift"))
        return extractPath
    }

    struct CanonicalArchivingCase: Sendable, CustomStringConvertible {
        let name: String
        let isGit: Bool
        let extraFiles: [String]
        let mustBePresent: [String]

        var description: String { self.name }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
        arguments: [
            CanonicalArchivingCase(name: "git", isGit: true, extraFiles: [], mustBePresent: []),
            CanonicalArchivingCase(name: "nongit", isGit: false, extraFiles: [], mustBePresent: []),
            CanonicalArchivingCase(
                name: "nongit+canonical-metadata",
                isGit: false,
                extraFiles: [PackageRegistryCommand.Publish.metadataFilename],
                mustBePresent: [PackageRegistryCommand.Publish.metadataFilename]
            ),
        ],
    )
    func archivingProducesValidArchive(_ scenario: CanonicalArchivingCase) async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            if scenario.isGit {
                initGitRepo(packageDirectory)
            }

            for relativePath in scenario.extraFiles {
                let target = packageDirectory.appending(components: relativePath.split(separator: "/").map(String.init))
                try localFileSystem.createDirectory(target.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(target, bytes: "")
            }

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "1.0.0",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let extractedPath = try await Self.validateCanonicalArchive(at: archivePath)
            for relativePath in scenario.mustBePresent {
                let path = extractedPath.appending(components: relativePath.split(separator: "/").map(String.init))
                expectFileExists(at: path)
            }
            #expect(archivePath.isDescendant(of: workingDirectory))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
    )
    func archivingRejectsRepoWithoutCommits() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            initEmptyGitRepo(packageDirectory)

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            await #expect(
                performing: {
                    try await PackageArchiver.archive(
                        packageIdentity: packageIdentity,
                        packageVersion: "1.6.0",
                        packageDirectory: packageDirectory,
                        workingDirectory: workingDirectory,
                        workingFilesToCopy: [],
                        cancellator: .none,
                        observabilityScope: observability.topScope
                    )
                },
                throws: { error in
                    let message = "\(error)"
                    return message.contains("no commits") && message.contains(packageDirectory.pathString)
                }
            )
        }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
    )
    func archivingHonorsGitattributesExportIgnore() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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
            initGitRepo(packageDirectory)

            try localFileSystem.writeFileContents(
                packageDirectory.appending(component: ".gitattributes"),
                bytes: "secret/** export-ignore\n"
            )
            try localFileSystem.createDirectory(packageDirectory.appending(component: "secret"))
            try localFileSystem.writeFileContents(
                packageDirectory.appending(components: "secret", "data.txt"),
                bytes: "SECRET=leak"
            )
            let repo = GitRepository(path: packageDirectory)
            try repo.stageEverything()
            try repo.commit(message: "add secret dir with export-ignore")

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "2.1.0",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let extractedPath = try await Self.validateCanonicalArchive(at: archivePath)
            expectFileDoesNotExists(at: extractedPath.appending(components: "secret", "data.txt"))
            expectFileDoesNotExists(at: extractedPath.appending(component: ".gitattributes"))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
    )
    func archivingDoesNotMutateGitInfo() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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
            initGitRepo(packageDirectory)

            let attributesPath = packageDirectory.appending(components: ".git", "info", "attributes")

            // sub-case 1: no .git/info/attributes file before or after archiving
            #expect(!localFileSystem.exists(attributesPath))

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            _ = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "2.3.0",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            #expect(
                !localFileSystem.exists(attributesPath),
                "expected archiving not to create .git/info/attributes"
            )

            // sub-case 2: pre-existing .git/info/attributes content must be untouched
            let originalAttributes = "# user attributes\n*.md text eol=lf\n"
            try localFileSystem.createDirectory(attributesPath.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(attributesPath, string: originalAttributes)

            let workingDirectory2 = temporaryDirectory.appending(component: UUID().uuidString)
            _ = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "2.3.1",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory2,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let contentsAfter = try localFileSystem.readFileContents(attributesPath).description
            #expect(
                contentsAfter == originalAttributes,
                "expected .git/info/attributes to be unchanged; got \(contentsAfter.debugDescription)"
            )
        }
    }

    struct WorkingFilesArchivingCase: Sendable, CustomStringConvertible {
        struct Manifest: Sendable {
            let path: String
            let original: String?
            let replacement: String
        }

        let name: String
        let isGit: Bool
        let manifests: [Manifest]

        var description: String { self.name }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
        arguments: [
            WorkingFilesArchivingCase(
                name: "git+default-only",
                isGit: true,
                manifests: [
                    .init(path: "Package.swift", original: nil, replacement: "// signed default\n"),
                ]
            ),
            WorkingFilesArchivingCase(
                name: "git+multiple-manifests",
                isGit: true,
                manifests: [
                    .init(path: "Package.swift", original: nil, replacement: "// signed default\n"),
                    .init(path: "Package@swift-5.9.swift", original: "// original versioned\n", replacement: "// signed versioned\n"),
                ]
            ),
            WorkingFilesArchivingCase(
                name: "nongit+default-only",
                isGit: false,
                manifests: [
                    .init(path: "Package.swift", original: nil, replacement: "// signed default\n"),
                ]
            ),
        ],
    )
    func archivingInjectsWorkingFiles(_ scenario: WorkingFilesArchivingCase) async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            for manifest in scenario.manifests {
                if let original = manifest.original {
                    try localFileSystem.writeFileContents(
                        packageDirectory.appending(component: manifest.path),
                        string: original
                    )
                }
            }

            if scenario.isGit {
                initGitRepo(packageDirectory)
            }

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory, recursive: true)

            for manifest in scenario.manifests {
                try localFileSystem.writeFileContents(
                    workingDirectory.appending(manifest.path),
                    string: manifest.replacement
                )
            }

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "3.0.0",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: scenario.manifests.map(\.path),
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let extractedPath = try await Self.validateCanonicalArchive(at: archivePath)
            for manifest in scenario.manifests {
                let archived = try localFileSystem.readFileContents(
                    extractedPath.appending(manifest.path)
                ).description
                #expect(
                    archived == manifest.replacement,
                    "expected '\(manifest.path)' to contain replacement; got \(archived.debugDescription)"
                )
            }
            expectFileExists(at: extractedPath.appending(components: "Sources", "MyPackage", "MyPackage.swift"))
        }
    }

    struct SymlinkArchivingCase: Sendable, CustomStringConvertible {
        let name: String
        let isGit: Bool
        let targetIsOutsidePackage: Bool
        let errorContains: String?

        var description: String { self.name }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
        arguments: [
            SymlinkArchivingCase(name: "git+escaping",    isGit: true,  targetIsOutsidePackage: true,  errorContains: "escaping-link"),
            SymlinkArchivingCase(name: "nongit+escaping", isGit: false, targetIsOutsidePackage: true,  errorContains: "escaping-link"),
            SymlinkArchivingCase(name: "intree+relative", isGit: false, targetIsOutsidePackage: false, errorContains: nil),
        ],
    )
    func archivingRejectsEscapingSymlinks(_ scenario: SymlinkArchivingCase) async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            let symlinkName: String
            let symlinkTarget: AbsolutePath
            if scenario.targetIsOutsidePackage {
                symlinkName = "escaping-link"
                symlinkTarget = temporaryDirectory.appending("outside-target")
                try localFileSystem.writeFileContents(symlinkTarget, bytes: "outside")
            } else {
                symlinkName = "internal-link"
                symlinkTarget = packageDirectory.appending(components: "Sources", "MyPackage", "MyPackage.swift")
            }
            try localFileSystem.createSymbolicLink(
                packageDirectory.appending(symlinkName),
                pointingAt: symlinkTarget,
                relative: !scenario.targetIsOutsidePackage
            )

            if scenario.isGit {
                initGitRepo(packageDirectory)
            }

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            if let needle = scenario.errorContains {
                await #expect(
                    performing: {
                        try await PackageArchiver.archive(
                            packageIdentity: packageIdentity,
                            packageVersion: "4.0.0",
                            packageDirectory: packageDirectory,
                            workingDirectory: workingDirectory,
                            workingFilesToCopy: [],
                            cancellator: .none,
                            observabilityScope: observability.topScope
                        )
                    },
                    throws: { "\($0)".contains(needle) }
                )
            } else {
                _ = try await PackageArchiver.archive(
                    packageIdentity: packageIdentity,
                    packageVersion: "4.0.0",
                    packageDirectory: packageDirectory,
                    workingDirectory: workingDirectory,
                    workingFilesToCopy: [],
                    cancellator: .none,
                    observabilityScope: observability.topScope
                )
            }
        }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
    )
    func archivingRejectsCommittedSymlinkReplacedInWorkingTree() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            let outsideTarget = temporaryDirectory.appending("outside-target")
            try localFileSystem.writeFileContents(outsideTarget, bytes: "secret")
            let symlinkPath = packageDirectory.appending("evil-link")
            try localFileSystem.createSymbolicLink(
                symlinkPath,
                pointingAt: outsideTarget,
                relative: false
            )

            initGitRepo(packageDirectory)

            try localFileSystem.removeFileTree(symlinkPath)
            try localFileSystem.writeFileContents(symlinkPath, bytes: "harmless")

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(workingDirectory, recursive: true)
            try localFileSystem.writeFileContents(
                workingDirectory.appending("Package.swift"),
                bytes: "// replacement manifest"
            )

            await #expect(
                performing: {
                    try await PackageArchiver.archive(
                        packageIdentity: packageIdentity,
                        packageVersion: "4.0.0",
                        packageDirectory: packageDirectory,
                        workingDirectory: workingDirectory,
                        workingFilesToCopy: ["Package.swift"],
                        cancellator: .none,
                        observabilityScope: observability.topScope
                    )
                },
                throws: { "\($0)".contains("evil-link") }
            )
        }
    }

    struct FilteringArchivingCase: Sendable, CustomStringConvertible {
        let name: String
        let isGit: Bool
        let filesToCreate: [String]
        let mustBeAbsent: [String]

        var description: String { self.name }
    }

    @Test(
        .tags(
            .TestSize.large,
        ),
        .requiresWorkingDirectorySupport,
        arguments: [
            FilteringArchivingCase(
                name: "git+core-secrets",
                isGit: true,
                filesToCreate: [".env", "id_rsa", "credentials.json", ".netrc", "Sources/api.key"],
                mustBeAbsent: [".env", "id_rsa", "credentials.json", ".netrc", "Sources/api.key", ".gitignore"]
            ),
            FilteringArchivingCase(
                name: "nongit+core-secrets",
                isGit: false,
                filesToCreate: [".env", "id_rsa", "credentials.json", ".netrc", "Sources/api.key", ".gitattributes"],
                mustBeAbsent: [".env", "id_rsa", "credentials.json", ".netrc", "Sources/api.key", ".gitattributes", ".gitignore"]
            ),
            FilteringArchivingCase(
                name: "nongit+env-prefix",
                isGit: false,
                filesToCreate: [".env.production", ".env.local"],
                mustBeAbsent: [".env.production", ".env.local"]
            ),
            FilteringArchivingCase(
                name: "nongit+ssh-keypairs",
                isGit: false,
                filesToCreate: ["id_rsa", "id_rsa.pub", "id_ed25519", "id_ed25519.pub", "id_ecdsa", "id_ecdsa.pub"],
                mustBeAbsent: ["id_rsa", "id_rsa.pub", "id_ed25519", "id_ed25519.pub", "id_ecdsa", "id_ecdsa.pub"]
            ),
            FilteringArchivingCase(
                name: "nongit+cert-extensions",
                isGit: false,
                filesToCreate: ["server.pem", "cert.p12", "backup.pfx", "auth.key"],
                mustBeAbsent: ["server.pem", "cert.p12", "backup.pfx", "auth.key"]
            ),
            FilteringArchivingCase(
                name: "nongit+other-creds",
                isGit: false,
                filesToCreate: ["secrets.json", ".npmrc", "credentials"],
                mustBeAbsent: ["secrets.json", ".npmrc", "credentials"]
            ),
            FilteringArchivingCase(
                name: "nongit+nested-depth",
                isGit: false,
                filesToCreate: ["Sources/MyPackage/.env", "Sources/MyPackage/id_rsa"],
                mustBeAbsent: ["Sources/MyPackage/.env", "Sources/MyPackage/id_rsa"]
            ),
            FilteringArchivingCase(
                name: "nongit+ignored-dirs",
                isGit: false,
                filesToCreate: [".hg/data", ".svn/data", ".swiftpm/configuration", ".build/marker"],
                mustBeAbsent: [".hg/data", ".svn/data", ".swiftpm/configuration", ".build/marker", ".hg", ".svn", ".swiftpm", ".build"]
            ),
            FilteringArchivingCase(
                name: "nongit+uppercase-ignored-dirs",
                isGit: false,
                filesToCreate: [".GIT/config", ".Build/marker", ".SwiftPM/configuration", ".HG/data"],
                mustBeAbsent: [".GIT/config", ".Build/marker", ".SwiftPM/configuration", ".HG/data", ".GIT", ".Build", ".SwiftPM", ".HG"]
            ),
            FilteringArchivingCase(
                name: "nongit+ds-store",
                isGit: false,
                filesToCreate: [".DS_Store", "Sources/.DS_Store"],
                mustBeAbsent: [".DS_Store", "Sources/.DS_Store"]
            ),
        ],
    )
    func archivingFiltersSensitiveFiles(_ scenario: FilteringArchivingCase) async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let packageIdentity = PackageIdentity.plain("org.package")

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

            for relativePath in scenario.filesToCreate {
                let target = packageDirectory.appending(components: relativePath.split(separator: "/").map(String.init))
                try localFileSystem.createDirectory(target.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(target, bytes: "SECRET=leak")
            }

            if scenario.isGit {
                initGitRepo(packageDirectory)
            }

            let workingDirectory = temporaryDirectory.appending(component: UUID().uuidString)

            let archivePath = try await PackageArchiver.archive(
                packageIdentity: packageIdentity,
                packageVersion: "5.0.0",
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                workingFilesToCopy: [],
                cancellator: .none,
                observabilityScope: observability.topScope
            )

            let archiver = UniversalArchiver(localFileSystem)
            let extractPath = archivePath.parentDirectory.appending(component: UUID().uuidString)
            try localFileSystem.createDirectory(extractPath)
            try await archiver.extract(from: archivePath, to: extractPath)
            try localFileSystem.stripFirstLevel(of: extractPath)

            for relativePath in scenario.mustBeAbsent {
                let path = extractPath.appending(components: relativePath.split(separator: "/").map(String.init))
                expectFileDoesNotExists(at: path)
            }
            expectFileExists(at: extractPath.appending("Package.swift"))
            expectFileExists(at: extractPath.appending(components: "Sources", "MyPackage", "MyPackage.swift"))
        }
    }

    @Test(
        .tags(
            .TestSize.large,
            .Feature.Command.PackageRegistry.Publish,
        ),
        .requiresWorkingDirectorySupport,
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func publishingToHTTPRegistry(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug


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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func publishingToAllowedHTTPRegistry(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func publishingUnsignedPackage(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug
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
            let archiver = UniversalArchiver(localFileSystem)
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func publishingSignedPackage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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

            try fixture(name: "Signing") { fixturePath in
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

            try fixture(name: "Signing") { fixturePath in
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

            try fixture(name: "Signing") { fixturePath in
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
        try fixture(name: "Signing") { fixturePath in
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
        let archiver = UniversalArchiver(localFileSystem)
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
