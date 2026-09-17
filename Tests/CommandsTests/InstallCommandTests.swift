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
import Foundation
import Testing
import _InternalTestSupport

import class Basics.AsyncProcess
import struct SPMBuildCore.BuildSystemProvider

private let packageName = "ToolWithResources"
private let productName = "tool"
private let resourceBundleName = "\(packageName)_\(productName)" + hostTriple.nsbundleExtension

private func writeToolPackage(at packagePath: AbsolutePath) throws {
    try localFileSystem.writeFileContents(
        packagePath.appending("Package.swift"),
        string: """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(packageName)",
                targets: [
                    .executableTarget(
                        name: "\(productName)",
                        resources: [.copy("Resources/data.json")]
                    )
                ]
            )
            """
    )
    try localFileSystem.writeFileContents(
        packagePath.appending(components: "Sources", productName, "main.swift"),
        string: """
            import Foundation
            print(Bundle.module.bundlePath)
            """
    )
    try localFileSystem.writeFileContents(
        packagePath.appending(components: "Sources", productName, "Resources", "data.json"),
        string: "{}\n"
    )
}

@Suite(
    .tags(
        .TestSize.large,
        .Feature.Command.Package.ExperimentalInstall,
        .Feature.Command.Package.ExperimentalUninstall,
        .Feature.Resource,
    ),
)
struct InstallCommandTests {
    @Test(
        .issue("rdar://187600290", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func installsAndUninstallsResourceBundles(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let packagePath = tmpPath.appending("package")
            try writeToolPackage(at: packagePath)

            let env: Environment = ["XDG_CONFIG_HOME": tmpPath.appending("config").pathString]
            let installDir = tmpPath.appending(components: "config", "swiftpm", "bin")

            try await executeSwiftPackage(
                packagePath,
                configuration: .debug,
                extraArgs: ["experimental-install"],
                env: env,
                buildSystem: buildSystem,
            )

            expectFileExists(at: installDir.appending(productName))
            #expect(localFileSystem.exists(installDir.appending(resourceBundleName)))

            let stdout = try await AsyncProcess.checkNonZeroExit(
                args: installDir.appending(productName).pathString
            )
            #expect(
                stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    == installDir.appending(resourceBundleName).pathString
            )

            try await executeSwiftPackage(
                packagePath,
                configuration: .debug,
                extraArgs: ["experimental-uninstall", productName],
                env: env,
                buildSystem: buildSystem,
            )

            #expect(try localFileSystem.getDirectoryContents(installDir) == [])
        }
    }
}
