//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
@testable import Commands
@testable import CoreCommands
import PackageGraph
import PackageLoading
import PackageModel
import enum PackageModel.BuildConfiguration
import SPMBuildCore
import _InternalTestSupport
import TSCTestSupport
import Workspace
import Testing

struct BuildResult {
    let binPath: AbsolutePath
    let stdout: String
    let stderr: String
    let binContents: [String]
    let moduleContents: [String]
}

@discardableResult
fileprivate func execute(
    _ args: [String] = [],
    environment: Environment? = nil,
    packagePath: AbsolutePath? = nil,
    configuration: BuildConfiguration,
    buildSystem: BuildSystemProvider.Kind,
    throwIfCommandFails: Bool = true,
) async throws -> (stdout: String, stderr: String) {

    return try await executeSwiftBuild(
        packagePath,
        configuration: configuration,
        extraArgs: args,
        env: environment,
        buildSystem: buildSystem,
        throwIfCommandFails: throwIfCommandFails,
    )
}

fileprivate func build(
    _ args: [String],
    packagePath: AbsolutePath? = nil,
    configuration: BuildConfiguration,
    cleanAfterward: Bool = true,
    buildSystem: BuildSystemProvider.Kind,
) async throws -> BuildResult {
    do {
        let (stdout, stderr) = try await execute(args, packagePath: packagePath,configuration: configuration, buildSystem: buildSystem,)
        defer {
        }
        let (binPathOutput, _) = try await execute(
            ["--show-bin-path"],
            packagePath: packagePath,
            configuration: configuration,
            buildSystem: buildSystem,
        )
        let binPath = try AbsolutePath(validating: binPathOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        let binContents = try localFileSystem.getDirectoryContents(binPath).filter {
            guard let contents = try? localFileSystem.getDirectoryContents(binPath.appending(component: $0)) else {
                return true
            }
            // Filter directories which only contain an output file map since we didn't build anything for those which
            // is what `binContents` is meant to represent.
            return contents != ["output-file-map.json"]
        }
        var moduleContents: [String] = []
        switch buildSystem {
            case .native:
                moduleContents = (try? localFileSystem.getDirectoryContents(binPath.appending(component: "Modules"))) ?? []
            case .swiftbuild, .xcode:
                let moduleDirs = (try? localFileSystem.getDirectoryContents(binPath).filter {
                    $0.hasSuffix(".swiftmodule")
                }) ?? []
                for dir: String in moduleDirs {
                    moduleContents +=
                        (try? localFileSystem.getDirectoryContents(binPath.appending(component: dir)).map { "\(dir)/\($0)" }) ?? []
                }
        }

        if cleanAfterward {
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["clean"],
                buildSystem: buildSystem
            )
        }
        return BuildResult(
            binPath: binPath,
            stdout: stdout,
            stderr: stderr,
            binContents: binContents,
            moduleContents: moduleContents
        )
    } catch {
        if cleanAfterward {
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["clean"],
                buildSystem: buildSystem
            )
        }
        throw error
    }
}

@Suite(
    .serializedIfOnWindows,
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Build,
        .Feature.CommandLineArguments.BuildSystem,
    ),
)
struct BuildCommandTestCases {


    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func usage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let stdout = try await execute(["-help"], configuration: .debug, buildSystem: buildSystem).stdout
        #expect(stdout.contains("USAGE: swift build"))
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.ShowBinPath,
        ),
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData,
    )
    func binSymlink(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
        // Test is not implemented for Xcode build system
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)

            let targetPath = try fullPath.appending(components: buildSystem.binPath(for: configuration))
            let path = try await execute(
                ["--show-bin-path"],
                packagePath: fullPath,
                configuration: configuration,
                buildSystem: buildSystem,
            ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                AbsolutePath(path).pathString == targetPath.pathString
            )
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Help,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func seeAlso(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let stdout = try await execute(
            ["--help"],
            configuration: .debug,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("SEE ALSO: swift run, swift package, swift test"))
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Help,
        ),

        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func commandDoesNotEmitDuplicateSymbols(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let duplicateSymbolRegex = try #require(duplicateSymbolRegex)
        let (stdout, stderr) = try await execute(
            ["--help"],
            configuration: .debug,
            buildSystem: buildSystem,
        )
        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Version,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func version(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let stdout = try await execute(
            ["--version"],
            configuration: .debug,
            buildSystem: buildSystem,
        ).stdout
        let expectedRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(expectedRegex))
    }


    @Test(
        .tags(
            .Feature.CommandLineArguments.ExplicitTargetDependencyImportCheck,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9620", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func importOfMissedDepWarning(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            let error = await #expect(throws: SwiftPMError.self ) {
                try await build(
                    ["--explicit-target-dependency-import-check=warn"],
                    packagePath: fullPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }

            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            switch buildSystem {
                case .native:
                    #expect(
                        stderr.contains("warning: Target A imports another target (B) in the package without declaring it a dependency."),
                        "got stdout: \(stdout), stderr: \(stderr)",
                    )
                case .swiftbuild:
                    withKnownIssue {
                        #expect(
                            stderr.contains("warning: a dependency of main module 'A'"),
                            "got stdout: \(stdout), stderr: \(stderr)",
                        )
                    }
                case .xcode:
                    Issue.record("Test expectation have not been implemented")
                    break
            }
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.ExplicitTargetDependencyImportCheck,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9620", relationship: .defect),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func importOfMissedDepWarningVerifyingErrorFlow(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            let error = await #expect(throws: SwiftPMError.self ) {
                try await build(
                    ["--explicit-target-dependency-import-check=error"],
                    packagePath: fullPath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Expected error did not occur")
                return
            }

            switch buildSystem {
                case .native:
                    #expect(
                        stderr.contains("error: Target A imports another target (B) in the package without declaring it a dependency."),
                        "got stdout: \(stdout), stderr: \(stderr)",
                    )
                case .swiftbuild:
                    withKnownIssue {
                        #expect(
                            stderr.contains("error: a dependency of main module 'A'"),
                            "got stdout: \(stdout), stderr: \(stderr)",
                        )
                    }
                case .xcode:
                    Issue.record("Test expectatation have not been implemented.")
            }
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9620", relationship: .defect),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func importOfMissedDepWarningVerifyingDefaultDoesNotRunTheCheck(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            let error = await #expect(throws: SwiftPMError.self ) {
                try await build(
                    [],
                    packagePath: fullPath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Expected error did not occur")
                return
            }
            let mustNotBeMatches: String
            switch buildSystem {
                case .native:
                    mustNotBeMatches = "warning: Target A imports another target (B) in the package without declaring it a dependency."
                case .swiftbuild:
                    mustNotBeMatches = "warning: a dependency of main module 'A'"
                case .xcode:
                    mustNotBeMatches = "make compiler happy"
                    Issue.record("Test expectation has not been implemented")
            }
            #expect(!stderr.contains(mustNotBeMatches))
            #expect(!stdout.contains(mustNotBeMatches))
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func symlink(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)
                // Test symlink.
                try await execute(packagePath: fullPath, configuration: configuration, buildSystem: buildSystem)
                let actualDebug = try resolveSymlinks(fullPath.appending(components: buildSystem.binPath(for: configuration)))
                let expectedDebug = try fullPath.appending(components: buildSystem.binPath(for: configuration))
                #expect(actualDebug == expectedDebug)
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
              .Feature.Command.Build,
              .Feature.TargetType.Executable
        ),
        .IssueWindowsLongPath,
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData,
    )
    func buildExistingExecutableProductIsSuccessfull(
        data: BuildData,
    ) async throws {
        try await withKnownIssue("Failures possibly due to long file paths", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let result = try await build(
                    ["--product", "exec1"],
                    packagePath: fullPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.binContents.contains(executableName("exec1")))
                #expect(!result.binContents.contains("exec2.build"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9137", relationship: .defect),
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.CommandLineArguments.Product,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildExistingLibraryProductIsSuccessfull(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let (_, stderr) = try await execute(
                    ["--product", "lib1"],
                    packagePath: fullPath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                switch buildSystem {
                    case .native, .swiftbuild:
                        withKnownIssue("Found multiple targets named 'lib1'") {
                            #expect(
                                stderr.contains(
                                    "'--product' cannot be used with the automatic product 'lib1'; building the default target instead"
                                )
                            )
                        } when: {
                            .swiftbuild == buildSystem
                        }
                    case .xcode:
                        // Do nothing.
                        break
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9138", relationship: .defect),
        .tags(
            .Feature.CommandLineArguments.Target,
        ),
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData,
    )
    func buildExistingTargetIsSuccessfull(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        try await withKnownIssue("Could not find target named 'exec2'") {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let result = try await build(
                    ["--target", "exec2"],
                    packagePath: fullPath,
                    configuration: data.config,
                    buildSystem: buildSystem,
                )
                #expect(result.binContents.contains("exec2.build"))
                #expect(!result.binContents.contains(executableName("exec1")))
            }
        } when: {
            [
                .swiftbuild,
                .xcode,
            ].contains(buildSystem)
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Product,
            .Feature.CommandLineArguments.Target,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildProductAndTargetsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--product", "exec1", "--target", "exec2"],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(stderr.contains("error: '--product' and '--target' are mutually exclusive"))
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.BuildTests,
            .Feature.CommandLineArguments.Product,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildProductAndTestsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug

        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--product", "exec1", "--build-tests"],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(stderr.contains("error: '--product' and '--build-tests' are mutually exclusive"))
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.BuildTests,
            .Feature.CommandLineArguments.Target,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildTargetAndTestsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--build-tests", "--target", "exec2"],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(stderr.contains("error: '--target' and '--build-tests' are mutually exclusive"))
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.BuildTests,
            .Feature.CommandLineArguments.Product,
            .Feature.CommandLineArguments.Target,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnPlatform),
    )
    func buildProductTargetAndTestsFailsWithAMutuallyExclusiveMessage(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--build-tests", "--target", "exec2", "--product", "exec1"],
                    packagePath: fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            withKnownIssue(isIntermittent: true) {
                #expect(stderr.contains("error: '--product', '--target', and '--build-tests' are mutually exclusive"), "stout: \(stdout)")
            } when: {
                (
                    ProcessInfo.hostOperatingSystem == .windows && (
                        data.buildSystem == .native
                        || (data.buildSystem == .swiftbuild && data.config == .debug)
                        ))
            }
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Product,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildUnknownProductFailsWithAppropriateMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let productName = "UnknownProduct"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--product", productName],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            switch buildSystem {
                case .native:
                    #expect(stderr.contains("error: no product named '\(productName)'"))
                case .swiftbuild, .xcode:
                    let expectedErrorMessageRegex = try Regex("error: Could not find target named '\(productName).*'")
                    #expect(
                        stderr.contains(expectedErrorMessageRegex),
                        "expect log not emitted.\nstdout: '\(stdout)'\n\nstderr: '\(stderr)'",
                    )
            }
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Target,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildUnknownTargetFailsWithAppropriateMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let targetName = "UnknownTargetName"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--target", targetName],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            let expectedErrorMessage: String
            switch buildSystem {
                case .native:
                    expectedErrorMessage = "error: no target named '\(targetName)'"
                case .swiftbuild, .xcode:
                    expectedErrorMessage = "error: Could not find target named '\(targetName)'"
            }
            #expect(
                stderr.contains(expectedErrorMessage),
                "expect log not emitted.\nstdout: '\(stdout)'\n\nstderr: '\(stderr)'",
            )
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Product,
        ),
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData, ["ClangExecSingleFile", "SwiftExecSingleFile", "SwiftExecMultiFile"],
    )
    func atMainSupport(
        data: BuildData,
        executable: String,
    ) async throws {
        let buildSystem = data.buildSystem
        let config = data.config
        try await withKnownIssue(
            "SWBINTTODO: File not found or missing libclang errors on windows platforms. This needs to be investigated",
            isIntermittent: true,
        ) {
            try await fixture(name: "Miscellaneous/AtMainSupport") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)
                let result = try await build(
                    ["--product", executable],
                    packagePath: fullPath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                #expect(result.binContents.contains(executableName(executable)))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows  && buildSystem == .swiftbuild
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func nonReachableProductsAndTargetsFunctional(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
            let aPath = fixturePath.appending("A")

            let result = try await build(
                [],
                packagePath: aPath,
                configuration: config,
                buildSystem: buildSystem,
            )
            #expect(!result.binContents.contains("bexec"))
            #expect(!result.binContents.contains("BTarget2.build"))
            #expect(!result.binContents.contains("cexec"))
            #expect(!result.binContents.contains("CTarget.build"))
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Product,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func nonReachableProductsAndTargetsFunctionalWhereDependencyContainsADependentProducts(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        try await withKnownIssue("SWBINTTODO: Test failed. This needs to be investigated") {
            try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
                let aPath = fixturePath.appending("A")

                // Dependency contains a dependent product

                let result = try await build(
                    ["--product", "bexec"],
                    packagePath: aPath,
                    configuration: data.config,
                    buildSystem: buildSystem,
                )
                #expect(result.binContents.contains("BTarget2.build"))
                #expect(result.binContents.contains(executableName("bexec")))
                #expect(!result.binContents.contains(executableName("aexec")))
                #expect(!result.binContents.contains("ATarget.build"))
                #expect(!result.binContents.contains("BLibrary.a"))

                // FIXME: We create the modulemap during build planning, hence this ugliness.
                let bTargetBuildDir =
                ((try? localFileSystem.getDirectoryContents(result.binPath.appending("BTarget1.build"))) ?? [])
                    .filter { $0 != moduleMapFilename }
                #expect(bTargetBuildDir.isEmpty, "bTargetBuildDir should be empty")

                #expect(!result.binContents.contains("cexec"))
                #expect(!result.binContents.contains("CTarget.build"))

                // Also make sure we didn't emit parseable module interfaces
                // (do this here to avoid doing a second build in
                // testParseableInterfaces().
                #expect(!result.moduleContents.contains("ATarget.swiftinterface"))
                #expect(!result.moduleContents.contains("BTarget.swiftinterface"))
                #expect(!result.moduleContents.contains("CTarget.swiftinterface"))
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/pull/9130", relationship: .fixedBy),
        .tags(
            .Feature.CommandLineArguments.EnableParseableModuleInterfaces,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func parseableInterfaces(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            try await withKnownIssue(isIntermittent: true) {
                let result = try await build(
                    ["--enable-parseable-module-interfaces"],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                switch buildSystem {
                    case .native:
                        #expect(result.moduleContents.contains("A.swiftinterface"))
                        #expect(result.moduleContents.contains("B.swiftinterface"))
                    case .swiftbuild, .xcode:
                        let moduleARegex = try Regex(#"A[.]swiftmodule[/].*[.]swiftinterface"#)
                        let moduleBRegex = try Regex(#"B[.]swiftmodule[/].*[.]swiftmodule"#)
                        #expect(result.moduleContents.contains { $0.contains(moduleARegex) })
                        #expect(result.moduleContents.contains { $0.contains(moduleBRegex) })
                }
            } when: {
                // errors with SwiftBuild on Windows possibly due to long path on windows only for swift build
                ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
            }
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.Product,
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func automaticParseableInterfacesWithLibraryEvolution(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/LibraryEvolution") { fixturePath in
                let result = try await build(
                    [],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                switch buildSystem {
                    case .native:
                        #expect(result.moduleContents.contains("A.swiftinterface"))
                        #expect(result.moduleContents.contains("B.swiftinterface"))
                    case .swiftbuild, .xcode:
                        let moduleARegex = try Regex(#"A[.]swiftmodule[/].*[.]swiftinterface"#)
                        let moduleBRegex = try Regex(#"B[.]swiftmodule[/].*[.]swiftmodule"#)
                        withKnownIssue("SWBINTTODO: Test failed because of missing 'A.swiftmodule/*.swiftinterface' files") {
                            #expect(result.moduleContents.contains { $0.contains(moduleARegex) })
                        } when: {
                            buildSystem == .swiftbuild
                        }
                        #expect(result.moduleContents.contains { $0.contains(moduleBRegex) })
                }
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test
    func pifManifestFileIsCreatedInTheRootScratchPathDirectory() async throws {
        try await fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            try await withTemporaryDirectory { tmpDir in
                try await executeSwiftBuild(
                    fixturePath,
                    extraArgs: [
                        "--scratch-path",
                        tmpDir.pathString,
                    ],
                    buildSystem: .swiftbuild
                )
                expectFileExists(at: tmpDir.appending("manifest.pif"))
            }
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .tags(
            .Feature.BuildCache,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildCompleteMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
                let buildCompleteRegex = try Regex(#"Build complete!\s?(\([0-9]*\.[0-9]*\s*s(econds)?\))?"#)
                do {
                    let result = try await execute(
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                    // This test fails to match the 'Compiling' regex; rdar://101815761
                    // XCTAssertMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                    let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                    let lastLine = try #require(lines.last)
                    #expect(lastLine.contains(buildCompleteRegex))
                }

                do {
                    // test second time, to stabilize the cache
                    try await execute(
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                }

                do {
                    // test third time, to make sure message is presented even when nothing to build (cached)
                    let result = try await execute(
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                    // This test fails to match the 'Compiling' regex; rdar://101815761
                    // XCTAssertNoMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                    let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                    let lastLine = try #require(lines.last)
                    #expect(lastLine.contains(buildCompleteRegex))
                }
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows)
        }
    }

    @Test(
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData,
    )
    func buildStartMessage(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        let configuration =  data.config
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let result = try await execute([], packagePath: fixturePath, configuration: configuration, buildSystem: buildSystem, throwIfCommandFails: false)
            let expectedString: String
            switch configuration {
                case .debug:
                    expectedString = "debugging"
                case .release:
                    expectedString = "production"

            }
            switch buildSystem {
                case .native, .swiftbuild:
                    #expect(
                        result.stdout.contains("Building for \(expectedString)"),
                        "expect log not emitted.  got stdout: '\(result.stdout)'\n\nstderr '\(result.stderr)'",
                    )
                case .xcode:
                    // Xcode build system does not emit the build started message.
                    break
            }
        }
    }

    @Test(
        .IssueWindowsLongPath,
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildSystemDefaultSettings(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue("Sometimes failed to build due to a possible path issue", isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                // try await building using XCBuild with default parameters.  This should succeed.  We build verbosely so we get
                // full command lines.
                    let output: (stdout: String, stderr: String) = try await execute(
                        ["-v"],
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )

    #if os(macOS)
                // In the case of the native build system check for the cross-compile target, only for macOS
                if buildSystem == .native {
                    let targetTripleString = try UserToolchain.default.targetTriple.tripleString(forPlatformVersion: "")
                    #expect(output.stdout.contains("-target \(targetTripleString)"))
                }
    #endif

                // Look for build completion message from the particular build system
                #expect(output.stdout.contains("Build complete!"))
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows)
        }
    }

    @Test(
        .disabled("Disabled for now because it is hitting 'IR generation failure: Cannot read legacy layout file' in CI (rdar://88828632)"),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        .tags(
            .Feature.CommandLineArguments.VeryVerbose,
            .Feature.CommandLineArguments.Xlinker,
            .Feature.CommandLineArguments.Xcc,
            .Feature.CommandLineArguments.Xcxx,
            .Feature.CommandLineArguments.Xswiftc,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild, .xcode],
    )
    func xcodeBuildSystemWithAdditionalBuildFlags(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableMixed") { fixturePath in
            // try await building using XCBuild with additional flags.  This should succeed.  We build verbosely so we get
            // full command lines.
            let defaultOutput = try await execute(
                [
                    "--very-verbose",
                    "-Xlinker", "-rpath", "-Xlinker", "/fakerpath",
                    "-Xcc", "-I/cfakepath",
                    "-Xcxx", "-I/cxxfakepath",
                    "-Xswiftc", "-I/swiftfakepath",
                ],
                packagePath: fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            ).stdout

            // Look for certain things in the output from XCBuild.
            #expect(defaultOutput.contains("/fakerpath"))
            #expect(defaultOutput.contains("-I/cfakepath"))
            #expect(defaultOutput.contains("-I/cxxfakepath"))
            #expect(defaultOutput.contains("-I/swiftfakepath"))
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        .tags(
            .Feature.EnvironmentVariables.SWIFT_EXEC,
            .Feature.EnvironmentVariables.SWIFT_EXEC_MANIFEST,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild, .xcode],
    )
    func buildSystemOverrides(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let swiftCompilerPath = try UserToolchain.default.swiftCompilerPath
            // try await building without specifying overrides.  This should succeed, and should use the default
            // compiler path.
            let defaultOutput = try await execute(
                ["--vv"],
                packagePath: fixturePath,
                configuration: config,
                buildSystem: buildSystem,
            ).stdout
            #expect(defaultOutput.contains(swiftCompilerPath.pathString))

            // Now try await building while specifying a faulty compiler override.  This should fail.  Note that
            // we need to set the executable to use for the manifest itself to the default one, since it defaults to
            // SWIFT_EXEC if not provided.
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--vv"],
                    environment: [
                        "SWIFT_EXEC": "/usr/bin/false",
                        "SWIFT_EXEC_MANIFEST": swiftCompilerPath.pathString,
                    ],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(stderr.contains("/usr/bin/false"))
        }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.PrintManifestJobGraph,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func printLLBuildManifestJobGraph(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let output = try await execute(
                ["--print-manifest-job-graph"],
                packagePath: fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            ).stdout
            #expect(output.hasPrefix("digraph Jobs {"))
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.PrintPIFManifestGraph,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func printPIFManifestGraph(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let output = try await execute(
                ["--print-pif-manifest-graph"],
                packagePath: fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            ).stdout
            switch buildSystem {
                case .native, .xcode:
                    #expect(!output.hasPrefix("digraph PIF {"))
                case .swiftbuild:
                    #expect(output.hasPrefix("digraph PIF {"))
            }
        }
    }

    @Test(
        .SWBINTTODO("Swift build produces an error building the fixture for this test."),
        .tags(
            .Feature.CommandLineArguments.Xswiftc,
        ),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftDriverRawOutputGetsNewlines(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
         try await withKnownIssue(
            "error produced for this fixture",
            isIntermittent: true,
        ) {
            try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
                // Building with `-wmo` should result in a `remark: Incremental compilation has been disabled: it is not
                // compatible with whole module optimization` message, which should have a trailing newline.  Since that
                // message won't be there at all when the legacy compiler driver is used, we gate this check on whether the
                // remark is there in the first place.
                let result = try await execute(
                    ["-Xswiftc", "-wmo"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )
                if result.stdout.contains(
                    "remark: Incremental compilation has been disabled: it is not compatible with whole module optimization"
                ) {
                    #expect(result.stdout.contains("optimization\n"))
                    #expect(!result.stdout.contains("optimization["))
                    #expect(!result.stdout.contains("optimizationremark"))
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8659", "SWIFT_EXEC override is not working"),
        .SWBINTTODO("Test fails because the dummy-swiftc used in the test isn't accepted by swift-build. This needs to be investigated"),
        .tags(
            .Feature.EnvironmentVariables.SWIFT_EXEC,
            .Feature.EnvironmentVariables.SWIFT_ORIGINAL_PATH,
            .Feature.EnvironmentVariables.CUSTOM_SWIFT_VERSION,
            .Feature.CommandLineArguments.Verbose,
        ),
        buildDataUsingAllBuildSystemWithTags.tags,
        arguments: buildDataUsingAllBuildSystemWithTags.buildData,
    )
    func swiftGetVersion(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        let config = data.config
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            func findSwiftGetVersionFile() throws -> AbsolutePath {
                let buildArenaPath = fixturePath.appending(components: ".build", "debug")
                let files = try localFileSystem.getDirectoryContents(buildArenaPath)
                let filename = try #require(files.first { $0.hasPrefix("swift-version") })
                return buildArenaPath.appending(component: filename)
            }
            let dummySwiftcPath = SwiftPM.xctestBinaryPath(for: "dummy-swiftc")
            let swiftCompilerPath = try UserToolchain.default.swiftCompilerPath

            var environment: Environment = [
                "SWIFT_EXEC": dummySwiftcPath.pathString,
                // Environment variables used by `dummy-swiftc.sh`
                "SWIFT_ORIGINAL_PATH": swiftCompilerPath.pathString,
                "CUSTOM_SWIFT_VERSION": "1.0",
            ]

            try await withKnownIssue(
                "https://github.com/swiftlang/swift-package-manager/issues/8659, SWIFT_EXEC override is not working",
                isIntermittent: true
            ){
                // Build with a swiftc that returns version 1.0, we expect a successful build which compiles our one source
                // file.
                do {
                    let result = try await execute(
                        ["--verbose"],
                        environment: environment,
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                    #expect(
                        result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                        "compilation task missing from build result: \(result.stdout)",
                    )
                    #expect(
                        result.stdout.contains("Build complete!"),
                        "unexpected build result: \(result.stdout)",
                    )

                    let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                    let actualVersion = try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp()
                    #expect(actualVersion == "1.0")
                }

                // Build again with that same version, we do not expect any compilation tasks.
                do {
                    let result = try await execute(
                        ["--verbose"],
                        environment: environment,
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                    #expect(
                        !result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                        "compilation task present in build result: \(result.stdout)",
                    )
                    #expect(
                        result.stdout.contains("Build complete!"),
                        "unexpected build result: \(result.stdout)",
                    )

                    let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                    let actualVersion = try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp()
                    #expect(actualVersion == "1.0")
                }

                // Build again with a swiftc that returns version 2.0, we expect compilation happening once more.
                do {
                    environment["CUSTOM_SWIFT_VERSION"] = "2.0"
                    let result = try await execute(
                        ["--verbose"],
                        environment: environment,
                        packagePath: fixturePath,
                        configuration: config,
                        buildSystem: buildSystem,
                    )
                    #expect(
                        result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                        "compilation task missing from build result: \(result.stdout)",
                    )
                    #expect(
                        result.stdout.contains("Build complete!"),
                        "unexpected build result: \(result.stdout)",
                    )

                    let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                    let actualVersion = try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp()
                    #expect(actualVersion == "2.0")
                }
            } when: {
                (ProcessInfo.hostOperatingSystem == .windows)
                || ([.xcode, .swiftbuild].contains(buildSystem))
                || (buildSystem == .native && config == .release)
            }
        }
    }

    @Test(
        .SWBINTTODO("Test failed because swiftbuild doesn't output precis codesign commands. Once swift run works with swiftbuild the test can be investigated."),
        .tags(
            .Feature.CommandLineArguments.DisableGetTaskAllowEntitlement,
            .Feature.CommandLineArguments.EnableGetTaskAllowEntitlement,
            .Feature.CommandLineArguments.Verbose,
        ),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func getTaskAllowEntitlement(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
    #if os(macOS)
                // try await building with default parameters.  This should succeed. We build verbosely so we get full command
                // lines.
                var buildResult = try await build(["-v"], packagePath: fixturePath, configuration: .debug, buildSystem: buildSystem,)

                // TODO verification of the ad-hoc code signing can be done by `swift run` of the executable in these cases once swiftbuild build system is working with that
                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(["-v"], packagePath: fixturePath, configuration:.debug, buildSystem: buildSystem,)

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                // Build with different combinations of the entitlement flag and debug/release build configurations.

                buildResult = try await build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
    #else
                var buildResult = try await build(["-v"], packagePath: fixturePath, configuration: .debug, buildSystem: buildSystem,)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(["-v"], packagePath: fixturePath, configuration: .release,buildSystem: buildSystem,)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
                #expect(buildResult.stderr.contains(SwiftCommandState.entitlementsMacOSWarning))

                buildResult = try await build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
                #expect(buildResult.stderr.contains(SwiftCommandState.entitlementsMacOSWarning))
    #endif

                buildResult = try await build(["-v"], packagePath: fixturePath, configuration: .release, buildSystem: buildSystem)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
            }
        } when: {
            [.swiftbuild, .xcode].contains(buildSystem) && ProcessInfo.hostOperatingSystem != .linux
        }
    }

    @Test(
        .requireHostOS(.linux),
        .SWBINTTODO("Swift build doesn't currently ignore Linux main when linking on Linux. This needs further investigation."),
        .tags(
            .Feature.CommandLineArguments.BuildTests,
            .Feature.CommandLineArguments.EnableTestDiscovery,
            .Feature.CommandLineArguments.Verbose,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func ignoresLinuxMain(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/TestDiscovery/IgnoresLinuxMain") { fixturePath in
            let buildResult = try await build(
                ["-v", "--build-tests", "--enable-test-discovery"],
                packagePath: fixturePath,
                configuration: configuration,
                cleanAfterward: false,
                buildSystem: buildSystem,
            )
            let testBinaryPath = buildResult.binPath.appending("IgnoresLinuxMainPackageTests.xctest")

            switch buildSystem {
                case .native:
                    expectFileExists(at: testBinaryPath)
                    _ = try await AsyncProcess.checkNonZeroExit(arguments: [testBinaryPath.pathString])
                case .swiftbuild:
                    // there are no additional check
                    break
                case .xcode:
                    Issue.record("Test expectations have not been implemented.")
            }
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9299", relationship: .defect),
        .tags(
            .Feature.CommandLineArguments.Verbose,
            .Feature.CommandLineArguments.VeryVerbose,
            .Feature.CommandLineArguments.Xswiftc,
        ),
        arguments: SupportedBuildSystemOnPlatform, [
            ["--verbose"],
            ["--very-verbose"],
            ["-Xswiftc", "-diagnostic-style=llvm"],
        ]
    )
    func doesNotRebuildWithFlags(
        buildSystem: BuildSystemProvider.Kind,
        flags: [String],
    ) async throws {
        func buildSystemAndOutputLocation(
            buildSystem: BuildSystemProvider.Kind,
            configuration: BuildConfiguration,
        ) throws -> Basics.RelativePath {
            let base = try RelativePath(validating: ".build")
            let path = try base.appending(components: buildSystem.binPath(for: configuration, scratchPath: []))
            switch buildSystem {
                case .xcode:
                    return path.appending("ExecutableNew")
                case .swiftbuild:
                    return path.appending("ExecutableNew")
                case .native:
                    return path.appending("ExecutableNew.build")
                            .appending("main.swift.o")
            }
        }

        let config = BuildConfiguration.debug
        try await withKnownIssue(
            """
            Windows: Sometimes failed to build due to a possible path issue
            All: --very-verbose causes rebuild on SwiftBuild (https://github.com/swiftlang/swift-package-manager/issues/9299)
            """,
            isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                _ = try await build(
                    [],
                    packagePath: fixturePath,
                    configuration: config,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
                let mainOFile = try fixturePath.appending(buildSystemAndOutputLocation(buildSystem: buildSystem, configuration: config))
                let initialMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date

                _ = try await build(
                    flags,
                    packagePath: fixturePath,
                    configuration: config,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )

                let subsequentMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date
                #expect(initialMainOMtime == subsequentMainOMtime, "Expected no rebuild to occur when using flags \(flags), but the file was modified.")
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func parseAsLibraryCriteria(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ParseAsLibrary") { fixturePath in
                _ =  try await executeSwiftBuild(
                    fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func fatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        let expected = 0
        try await fixture(name: "Miscellaneous/Errors/FatalErrorInSingleXCTest/TypeLibrary") { fixturePath in
            // WHEN swift-build --build-tests is executed"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(
                    ["--build-tests"],
                    packagePath: fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            let matchString = "error: fatalError"
            let stdoutMatches = getNumberOfMatches(of: matchString, in: stdout)
            let stderrMatches = getNumberOfMatches(of: matchString, in: stderr)
            let actualNumMatches = stdoutMatches + stderrMatches

            // AND a fatal error message is printed \(expected) times
            #expect(actualNumMatches == expected)
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8844", relationship: .defect),
        .tags(
            .Feature.CommandLineArguments.Quiet,
        ),
    arguments: SupportedBuildSystemOnPlatform,
    )
     func swiftBuildQuietLogLevel(
         buildSystem: BuildSystemProvider.Kind,
     ) async throws {
         let configuration = BuildConfiguration.debug
         try await withKnownIssue(isIntermittent: true) {
             // GIVEN we have a simple test package
             try await fixture(name: "Miscellaneous/SwiftBuild") { fixturePath in
                //WHEN we build with the --quiet option
                let (stdout, stderr) = try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: ["--quiet"],
                    buildSystem: buildSystem
                )
                // THEN we should not see any output in stderr
                 #expect(stderr.isEmpty)
                // AND no content in stdout
                 #expect(stdout.isEmpty)
            }
         } when: {
            ProcessInfo.hostOperatingSystem == .windows &&
            buildSystem == .swiftbuild
         }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8844", relationship: .defect),
        .tags(
            .Feature.CommandLineArguments.Quiet,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftBuildQuietLogLevelWithError(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
         // GIVEN we have a simple test package
        try await fixture(name: "Miscellaneous/SwiftBuild") { fixturePath in
            let mainFilePath = fixturePath.appending("main.swift")
            try localFileSystem.removeFileTree(mainFilePath)
            try localFileSystem.writeFileContents(
            mainFilePath,
            string: """
                print("done"
                """
            )

            //WHEN we build with the --quiet option
            let error = await #expect(throws: SwiftPMError.self) {
                try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                extraArgs: ["--quiet"],
                buildSystem: buildSystem
                )
            }

            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            switch buildSystem {
                case .swiftbuild:
                    // THEN we should see output in stderr
                    #expect(stderr.isEmpty == false)
                    // AND no content in stdout
                    #expect(stdout.isEmpty)
                case .native, .xcode:
                    // THEN we should see content in stdout
                    #expect(stdout.isEmpty == false)
                    // AND no output in stderr
                    #expect(stderr.isEmpty)
            }
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.CommandLineArguments.Triple,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildingPackageWhichRequiresOlderDeploymentTarget(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        // This fixture specifies a deployment target of macOS 12, and uses API obsoleted in macOS 13. The goal
        // of this test is to ensure that SwiftPM respects the deployment target specified in the package manifest
        // when passed no triple of an unversioned triple, rather than using the latests deployment target.

        // No triple - build should pass
        try await fixture(name: "Miscellaneous/RequiresOlderDeploymentTarget") { path in
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true
                )
        }

        let hostArch: String
        #if arch(arm64)
        hostArch = "arm64"
        #elseif arch(x86_64)
        hostArch = "x86_64"
        #else
        Issue.record("test is not supported on host arch")
        return
        #endif

        // Unversioned triple - build should pass
        try await fixture(name: "Miscellaneous/RequiresOlderDeploymentTarget") { path in
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    extraArgs: ["--triple", "\(hostArch)-apple-macosx"],
                    buildSystem: buildSystem,
                    throwIfCommandFails: true
                )
        }

        // Versioned triple with supported deployment target - build should pass
        try await fixture(name: "Miscellaneous/RequiresOlderDeploymentTarget") { path in
                try await executeSwiftBuild(
                    path,
                    extraArgs: ["--triple", "\(hostArch)-apple-macosx12.0"],
                    buildSystem: buildSystem,
                    throwIfCommandFails: true
                )
        }

        // Versioned triple with unsupported deployment target - build should fail
        try await withKnownIssue {
            _ = try await fixture(name: "Miscellaneous/RequiresOlderDeploymentTarget") { path in
                await #expect(throws: Error.self) {
                    try await executeSwiftBuild(
                        path,
                        extraArgs: ["--triple", "\(hostArch)-apple-macosx14.0"],
                        buildSystem: buildSystem,
                        throwIfCommandFails: true
                    )
                }
            }
        } when: {
            // The native build system does not correctly pass the elevated deployment target
            buildSystem != .swiftbuild
        }
    }


    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.CommandLineArguments.Experimental.BuildDylibsAsFrameworks,
        ),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        arguments: getBuildData(for: [.swiftbuild]),
    )
    func dynamicLibrariesAsFrameworks(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/DynamicProduct") { fixturePath in
                let aPath = fixturePath.appending("exec")
                let result = try await build(
                    ["--experimental-build-dylibs-as-frameworks"],
                    packagePath: aPath,
                    configuration: data.config,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
                #expect(result.binContents.contains("PackageFrameworks"))
                #expect(result.binContents.contains("exec"))

                let frameworks = try localFileSystem.getDirectoryContents(result.binPath.appending("PackageFrameworks"))
                #expect(frameworks.contains("firstDyna.framework"))
                #expect(frameworks.contains("secondDyna.framework"))

            }
        } when: {
            data.config == .release
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
    )
    func trivialPackageResources() async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/TIF") { fixturePath in
            let result = try await build(
                [],
                packagePath: fixturePath,
                configuration: config,
                cleanAfterward: false,
                buildSystem: buildSystem,
            )
            try #require(result.binContents.contains("TIF_TIF.bundle"))
            let contentsDir = result.binPath.appending("TIF_TIF.bundle", "Contents")
            let bundleResourceDir = contentsDir.appending("Resources")

            let bundleResources = try localFileSystem.getDirectoryContents(bundleResourceDir)
            #expect(bundleResources.contains("some.txt"))
            #expect(bundleResources.contains("Assets.car"))
            #expect(bundleResources.contains("SomeAlert.nib"))

            // Check that the Info.plist of the resource bundle looks reasonable.  In particular, it shouldn't have a CFBundleExecutable key, since it's a codeless bundle.
            let infoPlistPath = contentsDir.appending("Info.plist")
            let infoPlistBytes = try localFileSystem.readFileContents(infoPlistPath)
            let infoPlist = try infoPlistBytes.withData({
                try #require(PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? NSDictionary, "couldn't parse built resource bundle's Info.plist as a property list")
            })
            #expect(infoPlist["CFBundleExecutable"] == nil, "Expected CFBundleExecutable to be omitted from the Info.plist of a codeless resource bundle")
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executableTargetIntegratedIntoTwoProducts(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Sometimes failed to build due to a possible path issue", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ExecutableTargetWithTwoProducts") { fixturePath in
                let config = BuildConfiguration.debug
                let _ = try await build(
                    [],
                    packagePath: fixturePath,
                    configuration: config,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }
}

extension Triple {
    func withoutVersion() throws -> Triple {
        if isDarwin() {
            let stringWithoutVersion = tripleString(forPlatformVersion: "")
            return try Triple(stringWithoutVersion)
        } else {
            return self
        }
    }
}



