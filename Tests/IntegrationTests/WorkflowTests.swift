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

import struct Basics.AbsolutePath
import protocol Basics.FileSystem
import var Basics.localFileSystem
import func Basics.withTemporaryDirectory
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import _InternalTestSupport

import Testing

@Suite(
    .tags(
        .TestSize.large,
        .UserWorkflow,
    ),
)
struct DeveloperWorkflowTests {

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/7098", relationship: .verifies),
        .requireHostOS(.macOS),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func buildTaskLocalInSandboxWithoutSandBox(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "TaskLocal/ExecutableTarget") { fixturePath in
            // GIVEN we have a command line that builds a package with `--disable-sanbox`
            let commandPrefix = [
                "/usr/bin/sandbox-exec",
                "-p",
                "(version 1)(allow default)",
            ]
            let cmd = getBuildSystemArgs(for: buildSystem) + configuration.buildArgs + [
                "--disable-sandbox",
                "--verbose",
            ]

            // WHEN we execute the command
            // THEN we expect it to build successfully.
            await #expect(throws: Never.self) {
                let (stdout, stderr) = try await SwiftPM.Build.execute(
                    cmd,
                    packagePath: fixturePath,
                    throwIfCommandFails: true,
                    commandPrefix: commandPrefix,
                )

                let swiftcInvocations = (stdout + stderr).split { $0.isNewline }.map(String.init).filter { $0.contains("swiftc") }

                // AND we expect there to be at least 1 swiftc invocation
                #expect(
                    swiftcInvocations.isEmpty == false,
                    "There should be at least 1 swiftc invocation",
                )

                // AND at least one of the swiftc invocations should contain `-disable-sandbox`
                let linesContainsExpectedDisableSandboxCompilerFlag = swiftcInvocations.filter { $0.contains("-disable-sandbox") }
                try #require(
                    linesContainsExpectedDisableSandboxCompilerFlag.isEmpty == false,
                    "There should be at least 1 swiftc invocation with `-disable-sandbox`",
                )
                // AND the number of invocation that have `-disable-sandbox` should not be more than the total number of `swiftc` invocations
                #expect(
                    linesContainsExpectedDisableSandboxCompilerFlag.count <= swiftcInvocations.count,
                )
            }
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10122", relationship: .verifies),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func addTargetDependencies(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: false) { packageRoot in
            let packageName = "MyPackage"
            try await executeSwiftPackage(
                packageRoot,
                configuration: .debug,
                extraArgs: [
                    "init",
                    "--type",
                    "library",
                    "--name",
                    packageName,
                ],
                buildSystem: buildSystem,
            )

            for name in ["TargetOne", "TargetTwo", "TargetThree"] {
                try await executeSwiftPackage(
                    packageRoot,
                    configuration: .debug,
                    extraArgs: [
                        "add-target",
                        name,
                    ],
                    buildSystem: buildSystem,
                )
            }
            for (target, pkgName) in [
                ("TargetOne", "MyPackage"),
                ("TargetTwo", "MyPackage"),
                ("TargetOne", "TargetThree"),
            ] {
                try await executeSwiftPackage(
                    packageRoot,
                    configuration: .debug,
                    extraArgs: [
                        "add-target-dependency",
                        target,
                        pkgName,
                    ],
                    buildSystem: buildSystem,
                )
            }

            await #expect(throws: Never.self) {
                try await executeSwiftPackage(
                    packageRoot,
                    configuration: .debug,
                    extraArgs: [
                        "dump-package",
                    ],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    @Test
    func scratchPathContainsSentinelFiles() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: false) { tmpDir in
            let packagePath = tmpDir.appending("packageUnderTest")
            let scratchPath = packagePath.appending(".build")
            let cacheDirTagFile = scratchPath.appending("CACHEDIR.TAG")
            let expectedDebugBuildSystemFile = scratchPath.appending(".buildSystem_\(BuildConfiguration.debug)")
            let expectedReleaseBuildSystemFile = scratchPath.appending(".buildSystem_\(BuildConfiguration.release)")

            let commonArgs = ["--package-path", packagePath.pathString]

            // Initialize the package
            try await executeSwiftPackage(
                packagePath,
                configuration: .debug,
                extraArgs: commonArgs + ["init", "--type", "library"],
                buildSystem: .swiftbuild,
            )

            // The package-path directory should exist
            try requireDirectoryExists(at: packagePath)
            // The scratch-path directory should not exist
            expectFileDoesNotExist(at: cacheDirTagFile)
            expectFileDoesNotExist(at: expectedDebugBuildSystemFile)
            expectFileDoesNotExist(at: expectedReleaseBuildSystemFile)
            try requireDirectoryDoesNotExist(at: scratchPath)

            // Build the package
            try await executeSwiftBuild(
                packagePath,
                configuration: .debug,
                extraArgs: commonArgs,
                buildSystem: .swiftbuild,
            )

            try requireDirectoryExists(at: packagePath)
            // The scratch-path directory should not exist
            expectFileExists(at: cacheDirTagFile)
            expectFileExists(at: expectedDebugBuildSystemFile)
            expectFileDoesNotExist(at: expectedReleaseBuildSystemFile)
            try expectBuildSystemFile(
                atScratchPath: scratchPath,
                with: .debug,
                contains: .swiftbuild,
            )
            try requireDirectoryExists(at: scratchPath)

            // Build the package using native
            try await executeSwiftBuild(
                packagePath,
                configuration: .debug,
                extraArgs: commonArgs,
                buildSystem: .native,
            )

            try expectBuildSystemFile(
                atScratchPath: scratchPath,
                with: .debug,
                contains: .native,
            )

            // Build the package with release using SwiftBuild and ensure the debug configuration still points to native
            try await executeSwiftBuild(
                packagePath,
                configuration: .release,
                extraArgs: commonArgs,
                buildSystem: .swiftbuild,
            )

            try expectBuildSystemFile(
                atScratchPath: scratchPath,
                with: .release,
                contains: .swiftbuild,
            )
            try expectBuildSystemFile(
                // Is set to the last build system
                atScratchPath: scratchPath,
                with: .debug,
                contains: .native,
            )
        }
    }
}


private func expectBuildSystemFile(
    atScratchPath path: AbsolutePath,
    with config: BuildConfiguration,
    contains: BuildSystemProvider.Kind,
    _ comment: Comment? = nil,
    fileSystem fs: FileSystem = localFileSystem,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let buildSystemFile = path.appending(".buildSystem_\(config)")
    let fileContents = try fs.readFileContents(buildSystemFile).description

    #expect(
        fileContents == "\(contains)",
        "Actual (\(fileContents))is not as expected (\(contains)). Read \(path)",
        sourceLocation: sourceLocation
    )
}
