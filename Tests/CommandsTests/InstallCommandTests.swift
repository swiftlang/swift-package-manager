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

private let sharedPackageName = "MultiToolPackage"
private let sharedModuleName = "SharedResources"
private let sharedBundleName = "\(sharedPackageName)_\(sharedModuleName)" + hostTriple.nsbundleExtension
private let sharingProductNames = ["toolA", "toolB"]

/// A package whose executable target carries its own resources.
private func writeToolPackage(at packagePath: AbsolutePath) throws {
    try writeManifest(
        at: packagePath,
        name: packageName,
        targets: """
            .executableTarget(
                name: "\(productName)",
                resources: [.copy("Resources/data.json")]
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

/// A package whose two executables both depend on one resource-carrying library, so they share a
/// single installed bundle.
private func writeSharedResourcePackage(at packagePath: AbsolutePath, resource: String) throws {
    let executableTargets = sharingProductNames
        .map { #".executableTarget(name: "\#($0)", dependencies: ["\#(sharedModuleName)"]),"# }
        .joined(separator: "\n")

    try writeManifest(
        at: packagePath,
        name: sharedPackageName,
        targets: """
            .target(
                name: "\(sharedModuleName)",
                resources: [.copy("Resources/data.json")]
            ),
            \(executableTargets)
            """
    )
    try localFileSystem.writeFileContents(
        packagePath.appending(components: "Sources", sharedModuleName, "\(sharedModuleName).swift"),
        string: """
            import Foundation
            public func resourceBundlePath() -> String { Bundle.module.bundlePath }
            """
    )
    try localFileSystem.writeFileContents(
        packagePath.appending(components: "Sources", sharedModuleName, "Resources", "data.json"),
        string: resource
    )
    for product in sharingProductNames {
        try localFileSystem.writeFileContents(
            packagePath.appending(components: "Sources", product, "main.swift"),
            string: """
                import \(sharedModuleName)
                print(resourceBundlePath())
                """
        )
    }
}

private func writeManifest(at packagePath: AbsolutePath, name: String, targets: String) throws {
    try localFileSystem.writeFileContents(
        packagePath.appending("Package.swift"),
        string: """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(name)",
                targets: [
                    \(targets)
                ]
            )
            """
    )
}

/// A package directory paired with an isolated install directory, and a runner wired to both.
private struct InstallFixture {
    let packagePath: AbsolutePath
    let installDir: AbsolutePath
    private let env: Environment
    private let buildSystem: BuildSystemProvider.Kind

    init(tmpPath: AbsolutePath, buildSystem: BuildSystemProvider.Kind) {
        self.packagePath = tmpPath.appending("package")
        self.installDir = tmpPath.appending(components: "config", "swiftpm", "bin")
        self.env = ["XDG_CONFIG_HOME": tmpPath.appending("config").pathString]
        self.buildSystem = buildSystem
    }

    @discardableResult
    func run(_ args: String...) async throws -> (stdout: String, stderr: String) {
        try await executeSwiftPackage(
            self.packagePath,
            configuration: .debug,
            extraArgs: args,
            env: self.env,
            buildSystem: self.buildSystem,
        )
    }

    func installed(_ name: String) -> AbsolutePath {
        self.installDir.appending(name)
    }
}

private func withInstallFixture(
    buildSystem: BuildSystemProvider.Kind,
    _ body: (InstallFixture) async throws -> Void
) async throws {
    try await testWithTemporaryDirectory { tmpPath in
        try await body(InstallFixture(tmpPath: tmpPath, buildSystem: buildSystem))
    }
}

private func expectNothingInstalled(
    in installDir: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    #expect(try localFileSystem.getDirectoryContents(installDir) == [], sourceLocation: sourceLocation)
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
        try await withInstallFixture(buildSystem: buildSystem) { fixture in
            try writeToolPackage(at: fixture.packagePath)

            try await fixture.run("experimental-install")

            expectFileExists(at: fixture.installed(productName))
            expectDirectoryExists(at: fixture.installed(resourceBundleName))

            let stdout = try await AsyncProcess.checkNonZeroExit(
                args: fixture.installed(productName).pathString
            )
            #expect(
                stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    == fixture.installed(resourceBundleName).pathString
            )

            try await fixture.run("experimental-uninstall", productName)

            try expectNothingInstalled(in: fixture.installDir)
        }
    }

    @Test(
        .issue("rdar://187600290", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func uninstallRefusesToRemoveModifiedFiles(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withInstallFixture(buildSystem: buildSystem) { fixture in
            try writeToolPackage(at: fixture.packagePath)

            try await fixture.run("experimental-install")

            let addedFile = fixture.installed(resourceBundleName).appending("added.txt")
            try localFileSystem.writeFileContents(addedFile, string: "not ours\n")

            await expectThrowsCommandExecutionError(
                try await fixture.run("experimental-uninstall", productName)
            ) { error in
                #expect(error.stderr.contains("modified since it was installed"))
            }

            expectFileExists(at: fixture.installed(productName))
            expectFileExists(at: addedFile)

            try localFileSystem.removeFileTree(addedFile)

            try await fixture.run("experimental-uninstall", productName)

            try expectNothingInstalled(in: fixture.installDir)
        }
    }

    @Test(
        .issue("rdar://187600290", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func sharedResourceBundleSurvivesUninstallingAnotherProduct(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withInstallFixture(buildSystem: buildSystem) { fixture in
            try writeSharedResourcePackage(at: fixture.packagePath, resource: "{}\n")

            for product in sharingProductNames {
                try await fixture.run("experimental-install", "--product", product)
            }

            try await fixture.run("experimental-uninstall", sharingProductNames[0])

            expectFileDoesNotExist(at: fixture.installed(sharingProductNames[0]))
            expectFileExists(at: fixture.installed(sharingProductNames[1]))
            expectDirectoryExists(at: fixture.installed(sharedBundleName))

            let stdout = try await AsyncProcess.checkNonZeroExit(
                args: fixture.installed(sharingProductNames[1]).pathString
            )
            #expect(
                stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    == fixture.installed(sharedBundleName).pathString
            )

            try await fixture.run("experimental-uninstall", sharingProductNames[1])

            try expectNothingInstalled(in: fixture.installDir)
        }
    }

    @Test(
        .issue("rdar://187600290", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func installingRefreshesRecordsOfProductsSharingAnUpdatedBundle(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withInstallFixture(buildSystem: buildSystem) { fixture in
            try writeSharedResourcePackage(at: fixture.packagePath, resource: "{}\n")

            try await fixture.run("experimental-install", "--product", sharingProductNames[0])

            try writeSharedResourcePackage(at: fixture.packagePath, resource: "{\"changed\": true}\n")

            let (_, stderr) = try await fixture.run(
                "experimental-install",
                "--product",
                sharingProductNames[1]
            )
            #expect(stderr.contains(sharedBundleName))

            for product in sharingProductNames {
                try await fixture.run("experimental-uninstall", product)
            }

            try expectNothingInstalled(in: fixture.installDir)
        }
    }
}
