//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import Testing
import Workspace
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider

@discardableResult
fileprivate func execute(
    _ args: [String] = [],
    packagePath: AbsolutePath? = nil,
) async throws -> (stdout: String, stderr: String) {
    let env: Environment = ["SWIFTPM_TESTS_PACKAGECACHE": "1"]
    return try await executeSwiftPackage(
        packagePath,
        extraArgs: args,
        env: env,
        buildSystem: .swiftbuild
    )
}

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct BuildCacheCommandTests {
    @Test
    func buildCachePackageLocalConfiguration() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let packageRoot = fixturePath.appending("Foo")
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]

            fs.createEmptyFiles(
                at: packageRoot,
                files:
                "/Package.swift",
            )

            try await execute(
                sharedConfig + [
                    "build-cache", "configure",
                    "--enable-caching",
                    "--size-limit", "10G",
                    "--enable-diagnostic-remarks",
                    "--remote-service-path", "/tmp/remote-service",
                    "--plugin-path", "/tmp/plugin",
                    "--enable-prefix-mapping",
                ],
                packagePath: packageRoot,
            )

            // Capture the first package's effective configuration.
            let (firstConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: packageRoot,
            )
            #expect(firstConfig.contains("build cache: enabled"))
            #expect(firstConfig.contains("size limit: 10G"))
            #expect(firstConfig.contains("diagnostic remarks: enabled"))
            #expect(firstConfig.contains("remote service path: /tmp/remote-service"))
            #expect(firstConfig.contains("plugin path: /tmp/plugin"))
            #expect(firstConfig.contains("prefix mapping: enabled"))

            // Configure a second package with different options.
            let secondPackageRoot = fixturePath.appending("Bar")
            fs.createEmptyFiles(
                at: secondPackageRoot,
                files:
                "/Package.swift",
            )

            try await execute(
                sharedConfig + [
                    "build-cache", "configure",
                    "--enable-caching",
                    "--size-limit", "20%",
                    "--disable-diagnostic-remarks",
                    "--disable-prefix-mapping",
                ],
                packagePath: secondPackageRoot,
            )

            let (secondConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: secondPackageRoot,
            )
            #expect(secondConfig.contains("build cache: enabled"))
            #expect(secondConfig.contains("size limit: 20% of available disk space"))
            #expect(secondConfig.contains("diagnostic remarks: disabled"))
            #expect(secondConfig.contains("prefix mapping: disabled"))
            #expect(!secondConfig.contains("remote service path"))
            #expect(!secondConfig.contains("plugin path"))

            // The first package's configuration should be unaffected by the second.
            let (firstConfigAgain, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: packageRoot,
            )
            #expect(firstConfigAgain.contains("build cache: enabled"))
            #expect(firstConfigAgain.contains("size limit: 10G"))
            #expect(firstConfigAgain.contains("diagnostic remarks: enabled"))
            #expect(firstConfigAgain.contains("remote service path: /tmp/remote-service"))
            #expect(firstConfigAgain.contains("plugin path: /tmp/plugin"))
            #expect(firstConfigAgain.contains("prefix mapping: enabled"))
        }
    }

    @Test
    func buildCacheGlobalConfiguration() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]

            let firstPackageRoot = fixturePath.appending("Foo")
            fs.createEmptyFiles(
                at: firstPackageRoot,
                files:
                "/Package.swift",
            )

            // Set a global configuration.
            try await execute(
                sharedConfig + [
                    "build-cache", "configure", "--global",
                    "--enable-caching",
                    "--size-limit", "10G",
                    "--enable-diagnostic-remarks",
                    "--enable-prefix-mapping",
                ],
                packagePath: firstPackageRoot,
            )

            // A package with no local configuration sees the global configuration.
            let (firstConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: firstPackageRoot,
            )
            #expect(firstConfig.contains("build cache: enabled"))
            #expect(firstConfig.contains("size limit: 10G"))
            #expect(firstConfig.contains("diagnostic remarks: enabled"))
            #expect(firstConfig.contains("prefix mapping: enabled"))

            // A second package overrides a single field with a package-local value.
            let secondPackageRoot = fixturePath.appending("Bar")
            fs.createEmptyFiles(
                at: secondPackageRoot,
                files:
                "/Package.swift",
            )

            try await execute(
                sharedConfig + ["build-cache", "configure", "--size-limit", "50%"],
                packagePath: secondPackageRoot,
            )

            let (secondConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: secondPackageRoot,
            )
            #expect(secondConfig.contains("size limit: 50% of available disk space"))
            #expect(secondConfig.contains("build cache: enabled"))
            #expect(secondConfig.contains("diagnostic remarks: enabled"))
            #expect(secondConfig.contains("prefix mapping: enabled"))

            let (firstConfigAgain, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: firstPackageRoot,
            )
            #expect(firstConfigAgain.contains("size limit: 10G"))
        }
    }

    @Test
    func buildCacheConfigurationFileContentsIsDeterministic() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let packageRoot = fixturePath.appending("Foo")
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]
            let configFile = Workspace.DefaultLocations.buildCacheConfigurationFile(
                forRootPackage: packageRoot
            )

            fs.createEmptyFiles(
                at: packageRoot,
                files:
                "/Package.swift",
            )

            let configureArgs = sharedConfig + [
                "build-cache", "configure",
                "--enable-caching",
                "--path", "/tmp/cache",
                "--size-limit", "10G",
                "--enable-diagnostic-remarks",
                "--remote-service-path", "/tmp/remote-service",
                "--plugin-path", "/tmp/plugin",
                "--enable-prefix-mapping",
            ]
            let resetArgs = sharedConfig + ["build-cache", "reset-configuration"]

            try await execute(configureArgs, packagePath: packageRoot)
            let expectedContent: String = try fs.readFileContents(configFile)
            try await execute(resetArgs, packagePath: packageRoot)
            #expect(!fs.isFile(configFile))

            for _ in 0..<4 {
                try await execute(configureArgs, packagePath: packageRoot)

                let content: String = try fs.readFileContents(configFile)
                #expect(content == expectedContent)

                try await execute(resetArgs, packagePath: packageRoot)
                #expect(!fs.isFile(configFile))
            }
        }
    }

    @Test
    func buildCacheResetDeletesConfigurationFile() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let packageRoot = fixturePath.appending("Foo")
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]
            let configFile = Workspace.DefaultLocations.buildCacheConfigurationFile(
                forRootPackage: packageRoot
            )

            fs.createEmptyFiles(
                at: packageRoot,
                files:
                "/Package.swift",
            )

            try await execute(
                sharedConfig + ["build-cache", "configure", "--enable-caching"],
                packagePath: packageRoot,
            )
            #expect(fs.isFile(configFile))

            try await execute(
                sharedConfig + ["build-cache", "reset-configuration"],
                packagePath: packageRoot,
            )
            #expect(!fs.isFile(configFile))
        }
    }

    @Test
    func buildCacheSizeLimitKindsReplaceEachOther() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let packageRoot = fixturePath.appending("Foo")
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]

            fs.createEmptyFiles(
                at: packageRoot,
                files:
                "/Package.swift",
            )

            // Start with an absolute size limit.
            try await execute(
                sharedConfig + ["build-cache", "configure", "--enable-caching", "--size-limit", "10G"],
                packagePath: packageRoot,
            )
            let (absoluteConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: packageRoot,
            )
            #expect(absoluteConfig.contains("size limit: 10G"))

            // Setting a percentage should replace the absolute size limit.
            try await execute(
                sharedConfig + ["build-cache", "configure", "--size-limit", "40%"],
                packagePath: packageRoot,
            )
            let (percentConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: packageRoot,
            )
            #expect(percentConfig.contains("size limit: 40% of available disk space"))

            // Setting an absolute size limit again should replace the percentage.
            try await execute(
                sharedConfig + ["build-cache", "configure", "--size-limit", "20G"],
                packagePath: packageRoot,
            )
            let (absoluteAgainConfig, _) = try await execute(
                sharedConfig + ["build-cache", "get-configuration"],
                packagePath: packageRoot,
            )
            #expect(absoluteAgainConfig.contains("size limit: 20G"))
        }
    }

    @Test
    func buildCacheInvalidSizeLimitIsRejected() async throws {
        try await testWithTemporaryDirectory { fixturePath in
            let fs = localFileSystem
            let packageRoot = fixturePath.appending("Foo")
            let sharedConfig = ["--config-path", fixturePath.appending("shared-config").pathString]

            fs.createEmptyFiles(
                at: packageRoot,
                files:
                "/Package.swift",
            )

            await expectThrowsCommandExecutionError(
                try await execute(
                    sharedConfig + ["build-cache", "configure", "--size-limit", "150%"],
                    packagePath: packageRoot,
                )
            ) { error in
                #expect(error.stderr.contains("The value '150%' is invalid for '--size-limit <size-limit>'"))
            }
        }
    }
}
