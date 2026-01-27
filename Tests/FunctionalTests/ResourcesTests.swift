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
import Foundation

import Basics
import PackageModel
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.large,
        .FunctionalArea.Resources,
    ),
)
struct ResourcesTests{
    @Test(
        .IssueWindowsRelativePathAssert,
        .IssueWindowsPathTestsFailures,
        .tags(
            .Feature.Command.Run,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func simpleResources(
        buildData: BuildData,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Resources/Simple") { fixturePath in
                var executables = ["SwiftyResource"]

                // Objective-C module requires macOS
                #if os(macOS)
                executables.append("SeaResource")
                executables.append("CPPResource")
                #endif

                for execName in executables {
                    let (output, _) = try await executeSwiftRun(
                        fixturePath,
                        execName,
                        configuration: buildData.config,
                        buildSystem: buildData.buildSystem,
                    )
                    #expect(output.contains("foo"))
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func localizedResources(
        buildData: BuildData
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await fixture(name: "Resources/Localized") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )

            let exec = try fixturePath.appending(components: buildSystem.binPath(for: configuration) + [executableName("exe")])
            // Note: <rdar://problem/59738569> Source from LANG and -AppleLanguages on command line for Linux resources
            let output = try await AsyncProcess.checkNonZeroExit(args: exec.pathString, "-AppleLanguages", "(en_US)").withSwiftLineEnding
            #expect(output == """
                ¡Hola Mundo!
                Hallo Welt!
                Bonjour le monde !

                """)
        }
    }

    @Test(
        .requireHostOS(.macOS),  // originally macOS only
        // .skipHostOS(.linux), // currently failing on Ubuntu
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9533", relationship: .defect),
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func resourcesInMixedClangPackage(
        buildData: BuildData,
    ) async throws {
        try await fixture(name: "Resources/Simple") { fixturePath in
            try await withKnownIssue(isIntermittent: true) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: buildData.config,
                    extraArgs: ["--target", "MixedClangResource"],
                    buildSystem: buildData.buildSystem,
                )
            } when: {
                [.windows, .linux].contains(ProcessInfo.hostOperatingSystem) // Test was originally enabled on macOS only
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func movedBinaryResources(
        buildData: BuildData,
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Resources/Moved") { fixturePath in
                var executables = ["SwiftyResource"]

                // Objective-C module requires macOS
                #if os(macOS)
                executables.append("SeaResource")
                #endif

                let binPath = try AbsolutePath(validating:
                    await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        extraArgs: ["--show-bin-path"],
                        buildSystem: buildSystem,
                    ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                for execName in executables {
                    _ = try await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        extraArgs: ["--product", execName],
                        buildSystem: buildSystem,
                    )

                    try await withTemporaryDirectory(prefix: execName) { tmpDirPath in
                        defer {
                            // Unblock and remove the tmp dir on deinit.
                            try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                            try? localFileSystem.removeFileTree(tmpDirPath)
                        }

                        let destBinPath = tmpDirPath.appending(component: executableName(execName))
                        // Move the binary
                        try localFileSystem.move(from: binPath.appending(component: executableName(execName)), to: destBinPath)
                        // Move the resources
                        try localFileSystem
                            .getDirectoryContents(binPath)
                            .filter { $0.contains(executableName(execName)) && $0.hasSuffix(".bundle") || $0.hasSuffix(".resources") }
                            .forEach { try localFileSystem.move(from: binPath.appending(component: $0), to: tmpDirPath.appending(component: $0)) }
                        // Run the binary
                        let output = try await AsyncProcess.checkNonZeroExit(args: destBinPath.pathString)
                        #expect(output.contains("foo"))
                    }
                }
            }
        } when: {
            // [2025-12-20T02:55:19.621Z]     SwiftyResource/resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named Resources_SwiftyResource
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,

    )
    func swiftResourceAccessorDoesNotCauseInconsistentImportWarning(
        buildData: BuildData,
    ) async throws {
        try await fixture(name: "Resources/FoundationlessClient/UtilsWithFoundationPkg") { fixturePath in
            try await withKnownIssue(isIntermittent: true) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: buildData.config,
                    Xswiftc: ["-warnings-as-errors"],
                    buildSystem: buildData.buildSystem,
                )
            } when: {
                // fails on native and SwiftBuild
                // failure on SwiftBuild is: [2025-12-20T02:52:32.562Z]     error: failed to save attachment: C:\Users\ContainerAdministrator\AppData\Local\Temp\Resources_FoundationlessClient_UtilsWithFoundationPkg.D2Ir4d\Resources_FoundationlessClient_UtilsWithFoundationPkg\.build\out\Intermediates.noindex\XCBuildData\2d5f9f79f8cadfc30e6f49d9f5323426.xcbuilddata\attachments\99a55b01714d8caeedaaca3a1ca6347f. Error: File exists but is not a directory: C:\Users\ContainerAdministrator\AppData\Local\Temp\Resources_FoundationlessClient_UtilsWithFoundationPkg.D2Ir4d\Resources_FoundationlessClient_UtilsWithFoundationPkg\.build\out\Intermediates.noindex\XCBuildData
                // failure on native is: [2025-12-20T02:52:32.562Z]     error: encountered an I/O error (code: 514) while reading \\?\C:\Users\ContainerAdministrator\AppData\Local\Temp\Resources_FoundationlessClient_UtilsWithFoundationPkg.0HOUUQ\Resources_FoundationlessClient_UtilsWithFoundationPkg\.build\x86_64-unknown-windows-msvc\debug\UtilsWithFoundationPkg.build\DerivedSources
                ProcessInfo.hostOperatingSystem == .windows
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments:buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func resourceBundleInClangPackageWhenRunningSwiftTest(
        buildData: BuildData,
    ) async throws {
        try await fixture(name: "Resources/Simple") { fixturePath in
            try await executeSwiftTest(
                fixturePath,
                configuration: buildData.config,
                extraArgs: ["--filter", "ClangResourceTests"],
                buildSystem: buildData.buildSystem,
            )
        }
    }

    @Test(
        .serialized, // crash occurs when executed in parallel. needs investigation
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9528", relationship: .defect),
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func resourcesEmbeddedInCode(
        buildData: BuildData,
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await withKnownIssue {
            try await fixture(name: "Resources/EmbedInCodeSimple") { fixturePath in
                let execPath = try fixturePath.appending(components: buildSystem.binPath(for: configuration) + [executableName("EmbedInCodeSimple")])
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let result = try await AsyncProcess.checkNonZeroExit(args: execPath.pathString)
                #expect(result.contains("hello world"))
                let resourcePath = fixturePath.appending(
                    components: "Sources", "EmbedInCodeSimple", "best.txt")

                // Check incremental builds
                for i in 0..<2 {
                    let content = "Hi there \(i)!"
                    // Update the resource file.
                    try localFileSystem.writeFileContents(resourcePath, string: content)
                    try await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                    // Run the executable again.
                    let result2 = try await AsyncProcess.checkNonZeroExit(args: execPath.pathString)
                    #expect(result2.contains("\(content)"))
                }
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .serialized, // crash occurs when executed in parallel. needs investigation
        .tags(
            .Feature.Command.Test,
        ),
        // .issue("", relationship: .defect),  TODO: Create GitHub issue
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func resourcesOutsideOfTargetCanBeIncluded(
        buildData: BuildData,
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await withKnownIssue {
            try await testWithTemporaryDirectory { tmpPath in
                let packageDir = tmpPath.appending(components: "MyPackage")

                let manifestFile = packageDir.appending("Package.swift")
                try localFileSystem.createDirectory(manifestFile.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(
                    manifestFile,
                    string: """
                    // swift-tools-version: 6.0
                    import PackageDescription
                    let package = Package(name: "MyPackage",
                        targets: [
                            .executableTarget(
                                name: "exec",
                                resources: [.copy("../resources")]
                            )
                        ])
                    """)

                let targetSourceFile = packageDir.appending(components: "Sources", "exec", "main.swift")
                try localFileSystem.createDirectory(targetSourceFile.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(targetSourceFile, string: """
                import Foundation
                print(Bundle.module.resourcePath ?? "<empty>")
                """)

                let resource = packageDir.appending(components: "Sources", "resources", "best.txt")
                try localFileSystem.createDirectory(resource.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(resource, string: "best")

                let (_, stderr) = try await executeSwiftBuild(
                    packageDir,
                    configuration: configuration,
                    env: ["SWIFT_DRIVER_SWIFTSCAN_LIB" : "/this/is/a/bad/path"],
                    buildSystem: buildSystem,
                )
                // Filter some unrelated output that could show up on stderr.
                let filteredStderr = stderr.components(separatedBy: "\n").filter { !$0.contains("[logging]") }
                                                                        .filter { !$0.contains("Unable to locate libSwiftScan") }.joined(separator: "\n")
                #expect(filteredStderr == "", "unexpectedly received error output: \(stderr)")

                let builtProductsDir = try packageDir.appending(components: buildSystem.binPath(for: configuration))
                // On Apple platforms, it's going to be `.bundle` and elsewhere `.resources`.
                let potentialResourceBundleName = try #require(localFileSystem.getDirectoryContents(builtProductsDir).filter { $0.hasPrefix("MyPackage_exec.") }.first)
                let resourcePath = builtProductsDir.appending(components: [potentialResourceBundleName, "resources", "best.txt"])
                #expect(localFileSystem.exists(resourcePath), "resource file wasn't copied by the build")
                let contents = try String(contentsOfFile: resourcePath.pathString)
                #expect(contents == "best", "unexpected resource contents: \(contents)")
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .macOS
        }
    }
}
