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
        // arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func scratchPathContainsSentinelFiles(
        // buildData: buildData,
    ) async throws {
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
            expectFileDoesNotExists(at: cacheDirTagFile)
            expectFileDoesNotExists(at: expectedDebugBuildSystemFile)
            expectFileDoesNotExists(at: expectedReleaseBuildSystemFile)
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
            expectFileDoesNotExists(at: expectedReleaseBuildSystemFile)
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
