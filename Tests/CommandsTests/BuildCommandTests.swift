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

@Suite(
    .tags(
        Tag.TestSize.small,
    ),
)
struct SanitierTests {
    @Test(
        arguments: Sanitizer.allCases
    )
    func creatingSanitizers(sanitizer: Sanitizer) throws {
            #expect(sanitizer == Sanitizer(argument: sanitizer.shortName))
    }

    @Test
    func invalidSanitizer() throws {
        #expect(Sanitizer(argument: "invalid") == nil)
    }
}

@Suite(
    .serialized, // to limit the number of swift executable running.
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Build,
    ),
)
struct BuildCommandTestCases {

    @discardableResult
    func execute(
        _ args: [String] = [],
        environment: Environment? = nil,
        packagePath: AbsolutePath? = nil,
        configuration: BuildConfiguration = .debug,
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

    func build(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        configuration: BuildConfiguration = .debug,
        cleanAfterward: Bool = true,
        buildSystem: BuildSystemProvider.Kind,
    ) async throws -> BuildResult {
        do {
            // let buildConfigurationArguments = isRelease ? ["-c", "release"] : []
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
            if buildSystem == .native {
                moduleContents = (try? localFileSystem.getDirectoryContents(binPath.appending(component: "Modules"))) ?? []
            } else {
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

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func usage(buildSystem: BuildSystemProvider.Kind) async throws {
        let stdout = try await execute(["-help"], buildSystem: buildSystem).stdout
        #expect(stdout.contains("USAGE: swift build"))
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,  BuildConfiguration.allCases
    )
    func binSymlink(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        // Test is not implemented for Xcode build system
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)
            
            let rootScrathPath = fullPath.appending(component: ".build")
            let targetPath: AbsolutePath
            if buildSystem == .xcode {
                targetPath =  rootScrathPath
            } else {
                targetPath = try rootScrathPath.appending(component: UserToolchain.default.targetTriple.platformBuildPathComponent)
            }
            let path = try await self.execute(["--show-bin-path"], packagePath: fullPath, configuration: configuration, buildSystem: buildSystem).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                AbsolutePath(path).pathString == targetPath
                .appending(components: buildSystem.binPathSuffixes(for: configuration)).pathString
            )
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func seeAlso(buildSystem: BuildSystemProvider.Kind) async throws {
        let stdout = try await execute(["--help"], buildSystem: buildSystem).stdout
        #expect(stdout.contains("SEE ALSO: swift run, swift package, swift test"))
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func commandDoesNotEmitDuplicateSymbols(buildSystem: BuildSystemProvider.Kind) async throws {
        let duplicateSymbolRegex = try #require(duplicateSymbolRegex)
        let (stdout, stderr) = try await execute(["--help"], buildSystem: buildSystem)
        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func version(buildSystem: BuildSystemProvider.Kind) async throws {
        let stdout = try await execute(["--version"], buildSystem: buildSystem).stdout
        let expectedRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(expectedRegex))
    }


    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func importOfMissedDepWarning(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("SWBINTTODO: Test fails because the warning message regarding missing imports is expected to be more verbose and actionable at the SwiftPM level with mention of the involved targets. This needs to be investigated. See case targetDiagnostic(TargetDiagnosticInfo) as a message type that may help.") {
            try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
                let fullPath = try resolveSymlinks(path)
                let error = await #expect(throws: SwiftPMError.self ) {
                    try await self.build(
                        ["--explicit-target-dependency-import-check=warn"],
                        packagePath: fullPath,
                        buildSystem: buildSystem,
                    )
                }
                guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }

                #expect(
                    stderr.contains("warning: Target A imports another target (B) in the package without declaring it a dependency."),
                    "got stdout: \(stdout), stderr: \(stderr)",
                )
            }
        } when: {
            [.swiftbuild, .xcode].contains(buildSystem)
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func importOfMissedDepWarningVerifyingErrorFlow(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("SWBINTTODO: Test fails because the warning message regarding missing imports is expected to be more verbose and actionable at the SwiftPM level with mention of the involved targets. This needs to be investigated. See case targetDiagnostic(TargetDiagnosticInfo) as a message type that may help.") {
            try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
                let fullPath = try resolveSymlinks(path)
                let error = await #expect(throws: SwiftPMError.self ) {
                    try await self.build(
                        ["--explicit-target-dependency-import-check=error"],
                        packagePath: fullPath,
                        buildSystem: buildSystem,
                    )
                }
                guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                    Issue.record("Expected error did not occur")
                    return
                }

                #expect(
                    stderr.contains("error: Target A imports another target (B) in the package without declaring it a dependency."),
                    "got stdout: \(String(describing: stdout)), stderr: \(String(describing: stderr))",
                )
            }
        } when: {
            [.swiftbuild, .xcode].contains(buildSystem)
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func importOfMissedDepWarningVerifyingDefaultDoesNotRunTheCheck(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.build([], packagePath: fullPath, buildSystem: buildSystem)
            }
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Expected error did not occur")
                return
            }
            #expect(
                !stderr.contains("warning: Target A imports another target (B) in the package without declaring it a dependency."),
                "got stdout: \(String(describing: stdout)), stderr: \(String(describing: stderr))",
            )
        }
    }

    @Test(
        .SWBINTTODO("Test fails because of a difference in the build layout. This needs to be updated to the expected path"),
        arguments: SupportedBuildSystemOnPlatform, BuildConfiguration.allCases
    )
    func symlink(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)
                let targetPath = try fullPath.appending(components:
                                                            ".build",
                                                        UserToolchain.default.targetTriple.platformBuildPathComponent
                )
                // Test symlink.
                let buildDir = fullPath.appending(components: ".build")
                try await self.execute(packagePath: fullPath, configuration: configuration, buildSystem: buildSystem)
                let actualDebug = try resolveSymlinks(buildDir.appending(components: buildSystem.binPathSuffixes(for: configuration)))
                let expectedDebug = targetPath.appending(components: buildSystem.binPathSuffixes(for: configuration))
                #expect(actualDebug == expectedDebug)
            }
        } when: {
            buildSystem != .native
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildExistingExecutableProductIsSuccessfull(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Failures possibly due to long file paths") {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let result = try await build(["--product", "exec1"], packagePath: fullPath, buildSystem: buildSystem,)
                #expect(result.binContents.contains(executableName("exec1")))
                #expect(!result.binContents.contains("exec2.build"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .SWBINTTODO("Found multiple targets named 'lib1'"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildExistingLibraryProductIsSuccessfull(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Found multiple targets named 'lib1'") {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let (_, stderr) = try await execute(["--product", "lib1"], packagePath: fullPath, buildSystem: buildSystem,)
                if buildSystem != .xcode {
                    #expect(
                        stderr.contains(
                            "'--product' cannot be used with the automatic product 'lib1'; building the default target instead"
                        )
                    )
                }
            }
        } when: {
            .swiftbuild == buildSystem
        }
    }

    @Test(
        .SWBINTTODO("Could not find target named 'exec2'"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildExistingTargetIsSuccessfull(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Could not find target named 'exec2'") {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                let result = try await build(["--target", "exec2"], packagePath: fullPath, buildSystem: buildSystem,)
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
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildProductAndTargetsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--product", "exec1", "--target", "exec2"],
                    packagePath: fixturePath,buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildProductAndTestsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--product", "exec1", "--build-tests"],
                    packagePath: fixturePath,buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildTargetAndTestsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--build-tests", "--target", "exec2"],
                    packagePath: fixturePath,buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildProductTargetAndTestsFailsWithAMutuallyExclusiveMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--build-tests", "--target", "exec2", "--product", "exec1"],
                    packagePath: fixturePath,buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(stderr.contains("error: '--product', '--target', and '--build-tests' are mutually exclusive"))
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildUnknownProductFailsWithAppropriateMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let productName = "UnknownProduct"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--product", productName],
                    packagePath: fixturePath,buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            try withKnownIssue {
                if .native == buildSystem {
                    #expect(stderr.contains("error: no product named '\(productName)'"))
                } else {
                    let expectedErrorMessageRegex = try Regex("error: Could not find target named '\(productName).*'")
                    #expect(
                        stderr.contains(expectedErrorMessageRegex),
                        "expect log not emitted.\nstdout: '\(stdout)'\n\nstderr: '\(stderr)'",
                    )
                }
            } when: {
                buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildUnknownTargetFailsWithAppropriateMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let targetName = "UnknownTargetName"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                ["--target", targetName],
                    packagePath: fixturePath,buildSystem: buildSystem,
                )
            }
            // THEN I expect a failure
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            let expectedErrorMessage: String
            if .native == buildSystem {
                expectedErrorMessage = "error: no target named '\(targetName)'"
            } else {
                expectedErrorMessage = "error: Could not find target named '\(targetName)'"
            }
            withKnownIssue{
                #expect(
                    stderr.contains(expectedErrorMessage),
                    "expect log not emitted.\nstdout: '\(stdout)'\n\nstderr: '\(stderr)'",
                )
            } when: {
                buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func atMainSupport(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("SWBINTTODO: File not found or missing libclang errors on non-macOS platforms. This needs to be investigated") {
            try await fixture(name: "Miscellaneous/AtMainSupport") { fixturePath in
                let fullPath = try resolveSymlinks(fixturePath)

                do {
                    let result = try await build(["--product", "ClangExecSingleFile"], packagePath: fullPath, buildSystem: buildSystem)
                    #expect(result.binContents.contains(executableName("ClangExecSingleFile")))
                }

                do {
                    let result = try await build(["--product", "SwiftExecSingleFile"], packagePath: fullPath, buildSystem: buildSystem)
                    #expect(result.binContents.contains(executableName("SwiftExecSingleFile")))
                }

                do {
                    let result = try await build(["--product", "SwiftExecMultiFile"], packagePath: fullPath, buildSystem: buildSystem)
                    #expect(result.binContents.contains(executableName("SwiftExecMultiFile")))
                }
            }
        } when: {
            ![.macOS, .linux].contains(ProcessInfo.hostOperatingSystem)  && buildSystem == .swiftbuild
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func nonReachableProductsAndTargetsFunctional(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        // skipped on Xcode
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
                let aPath = fixturePath.appending("A")

                let result = try await build([], packagePath: aPath, buildSystem: buildSystem)
                #expect(!result.binContents.contains("bexec"))
                #expect(!result.binContents.contains("BTarget2.build"))
                #expect(!result.binContents.contains("cexec"))
                #expect(!result.binContents.contains("CTarget.build"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func nonReachableProductsAndTargetsFunctionalWhereDependencyContainsADependentProducts(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        // skipped on Xcode
        // known failures in SwiftBuild
        try await withKnownIssue("SWBINTTODO: Test failed. This needs to be investigated") {
            try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
                let aPath = fixturePath.appending("A")

                // Dependency contains a dependent product

                let result = try await build(["--product", "bexec"], packagePath: aPath, buildSystem: buildSystem)
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
            buildSystem != .native
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func parseableInterfaces(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            try await withKnownIssue {
                let result = try await build(["--enable-parseable-module-interfaces"], packagePath: fixturePath, buildSystem: buildSystem)
                switch buildSystem {
                    case .native:
                        #expect(result.moduleContents.contains("A.swiftinterface"))
                        #expect(result.moduleContents.contains("B.swiftinterface"))
                    default:
                    let moduleARegex = try Regex(#"A[.]swiftmodule[/].*[.]swiftinterface"#)
                    let moduleBRegex = try Regex(#"B[.]swiftmodule[/].*[.]swiftmodule"#)
                    #expect(result.moduleContents.contains { $0.contains(moduleARegex) })
                    #expect(result.moduleContents.contains { $0.contains(moduleBRegex) })
                }
            } when: {
                // errors with SwiftBuild on Windows possibly due to long path on windows only for swift build
                buildSystem == .xcode || (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func automaticParseableInterfacesWithLibraryEvolution(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/LibraryEvolution") { fixturePath in
                let result = try await build([], packagePath: fixturePath, buildSystem: buildSystem)
                switch buildSystem {
                    case .native:
                        #expect(result.moduleContents.contains("A.swiftinterface"))
                        #expect(result.moduleContents.contains("B.swiftinterface"))
                    default:
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

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildCompleteMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
                let buildCompleteRegex = try Regex(#"Build complete!\s?(\([0-9]*\.[0-9]*\s*s(econds)?\))?"#)
                do {
                    let result = try await execute(packagePath: fixturePath, buildSystem: buildSystem)
                    // This test fails to match the 'Compiling' regex; rdar://101815761
                    // XCTAssertMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                    let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                    let lastLine = try #require(lines.last)
                    #expect(lastLine.contains(buildCompleteRegex))
                }

                do {
                    // test second time, to stabilize the cache
                    try await self.execute(packagePath: fixturePath, buildSystem: buildSystem)
                }

                do {
                    // test third time, to make sure message is presented even when nothing to build (cached)
                    let result = try await execute(packagePath: fixturePath, buildSystem: buildSystem)
                    // This test fails to match the 'Compiling' regex; rdar://101815761
                    // XCTAssertNoMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                    let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                    let lastLine = try #require(lines.last)
                    #expect(lastLine.contains(buildCompleteRegex))
                }
            }
        } when: {
            buildSystem == .swiftbuild && ((ProcessInfo.hostOperatingSystem == .windows))
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform, BuildConfiguration.allCases,
    )
    func buildStartMessage(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let result = try await execute([], packagePath: fixturePath, configuration: configuration, buildSystem: buildSystem, throwIfCommandFails: false)
            let expectedString: String
            switch configuration {
                case .debug:
                    expectedString = "debugging"
                case .release:
                    expectedString = "production"

            }
            withKnownIssue("Xcode build system does not emit the build started message.") {
                #expect(
                    result.stdout.contains("Building for \(expectedString)"),
                    "expect log not emitted.  got stdout: '\(result.stdout)'\n\nstderr '\(result.stderr)'")
            } when: {
                buildSystem == .xcode || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline)
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func buildSystemDefaultSettings(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Sometimes failed to build due to a possible path issue", isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                // try await building using XCBuild with default parameters.  This should succeed.  We build verbosely so we get
                // full command lines.
                    let output: (stdout: String, stderr: String) = try await execute(
                        ["-v"],
                        packagePath: fixturePath,
                        configuration: .debug,
                        buildSystem: buildSystem,
                    )

                // In the case of the native build system check for the cross-compile target, only for macOS
    #if os(macOS)
                if buildSystem == .native {
                    let targetTripleString = try UserToolchain.default.targetTriple.tripleString(forPlatformVersion: "")
                    #expect(output.stdout.contains("-target \(targetTripleString)"))
                }
    #endif

                // Look for build completion message from the particular build system
                #expect(output.stdout.contains("Build complete!"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .disabled("Disabled for now because it is hitting 'IR generation failure: Cannot read legacy layout file' in CI (rdar://88828632)"),
        arguments: [BuildSystemProvider.Kind.swiftbuild, .xcode], BuildConfiguration.allCases
    )
    func xcodeBuildSystemWithAdditionalBuildFlags(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration
    ) async throws {
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
        arguments: [BuildSystemProvider.Kind.xcode],
    )
    func buildSystemOverrides(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let swiftCompilerPath = try UserToolchain.default.swiftCompilerPath
            // try await building without specifying overrides.  This should succeed, and should use the default
            // compiler path.
            let defaultOutput = try await self.execute(
                ["--vv"],
                packagePath: fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            ).stdout
            #expect(defaultOutput.contains(swiftCompilerPath.pathString))

            // Now try await building while specifying a faulty compiler override.  This should fail.  Note that
            // we need to set the executable to use for the manifest itself to the default one, since it defaults to
            // SWIFT_EXEC if not provided.
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                    ["--vv"],
                    environment: [
                        "SWIFT_EXEC": "/usr/bin/false",
                        "SWIFT_EXEC_MANIFEST": swiftCompilerPath.pathString,
                    ],
                    packagePath: fixturePath,
                    configuration: .debug,
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
        arguments: SupportedBuildSystemOnPlatform, BuildConfiguration.allCases
    )
    func printLLBuildManifestJobGraph(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration
    ) async throws {
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
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftDriverRawOutputGetsNewlines(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("SWBINTTODO: Swift build produces an error building the fixture for this test.") {
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
            ProcessInfo.hostOperatingSystem != .macOS && buildSystem == .swiftbuild
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8659", "SWIFT_EXEC override is not working"),
        .SWBINTTODO("Test fails because the dummy-swiftc used in the test isn't accepted by swift-build. This needs to be investigated"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftGetVersion(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {

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

            try await withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8659, SWIFT_EXEC override is not working"){


                // Build with a swiftc that returns version 1.0, we expect a successful build which compiles our one source
                // file.
                do {
                    let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath, buildSystem: buildSystem)
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
                    let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath, buildSystem: buildSystem)
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
                    let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath, buildSystem: buildSystem)
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
                (ProcessInfo.hostOperatingSystem == .windows) || ([.xcode, .swiftbuild].contains(buildSystem))
            }
        }
    }

    @Test(
        .SWBINTTODO("Test failed because swiftbuild doesn't output precis codesign commands. Once swift run works with swiftbuild the test can be investigated."),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func getTaskAllowEntitlement(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
    #if os(macOS)
                // try await building with default parameters.  This should succeed. We build verbosely so we get full command
                // lines.
                var buildResult = try await build(["-v"], packagePath: fixturePath, buildSystem: buildSystem,)

                // TODO verification of the ad-hoc code signing can be done by `swift run` of the executable in these cases once swiftbuild build system is working with that
                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(["-v"], packagePath: fixturePath, configuration:.debug, buildSystem: buildSystem,)

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                // Build with different combinations of the entitlement flag and debug/release build configurations.

                buildResult = try await self.build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )

                #expect(buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
    #else
                var buildResult = try await self.build(["-v"], packagePath: fixturePath, buildSystem: buildSystem,)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(["-v"], packagePath: fixturePath, configuration: .release,buildSystem: buildSystem,)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))

                buildResult = try await self.build(
                    ["--disable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
                #expect(buildResult.stderr.contains(SwiftCommandState.entitlementsMacOSWarning))

                buildResult = try await self.build(
                    ["--enable-get-task-allow-entitlement", "-v"],
                    packagePath: fixturePath,
                    configuration: .release,
                    buildSystem: buildSystem,
                )

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
                #expect(buildResult.stderr.contains(SwiftCommandState.entitlementsMacOSWarning))
    #endif

                buildResult = try await self.build(["-v"], packagePath: fixturePath, configuration: .release, buildSystem: buildSystem)

                #expect(!buildResult.stdout.contains("codesign --force --sign - --entitlements"))
            }
        } when: {
            [.swiftbuild, .xcode].contains(buildSystem)
        }
    }

    @Test(
        .requireHostOS(.linux),
        .SWBINTTODO("Swift build doesn't currently ignore Linux main when linking on Linux. This needs further investigation."),
        arguments: SupportedBuildSystemOnPlatform, BuildConfiguration.allCases,
    )
    func ignoresLinuxMain(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/TestDiscovery/IgnoresLinuxMain") { fixturePath in
                let buildResult = try await self.build(
                    ["-v", "--build-tests", "--enable-test-discovery"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
                let testBinaryPath = buildResult.binPath.appending("IgnoresLinuxMainPackageTests.xctest")

                _ = try await AsyncProcess.checkNonZeroExit(arguments: [testBinaryPath.pathString])
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    private static func buildSystemAndOutputLocation() throws -> [(BuildSystemProvider.Kind, Basics.RelativePath)] {
        return try SupportedBuildSystemOnPlatform.map { buildSystem in
            let triple = try UserToolchain.default.targetTriple.withoutVersion()
            let base = try RelativePath(validating: ".build")
            let debugFolderComponents = buildSystem.binPathSuffixes(for: .debug)
            switch buildSystem {
                case .xcode:
                    let path = base.appending(components: debugFolderComponents)
                    return (
                        buildSystem,
                        triple.platformName() == "macosx" ? path.appending("ExecutableNew") : path
                            .appending("ExecutableNew.swiftmodule")
                            .appending("Project")
                            .appending("\(triple).swiftsourceinfo")
                    )
                case .swiftbuild:
                    let path = base.appending(triple.tripleString)
                        .appending(components: debugFolderComponents)
                    return (
                        buildSystem,
                        triple.platformName() == "macosx" ? path.appending("ExecutableNew") : path
                            .appending("ExecutableNew.swiftmodule")
                            .appending("Project")
                            .appending("\(triple).swiftsourceinfo")
                    )
                case .native:
                    return (
                        buildSystem,
                        base.appending(components: debugFolderComponents)
                            .appending("ExecutableNew.build")
                            .appending("main.swift.o")
                    )
            }
        }
    }

    @Test(arguments: try buildSystemAndOutputLocation())
    func doesNotRebuildWithVerboseFlag(
        buildSystem: BuildSystemProvider.Kind,
        outputFile: Basics.RelativePath
    ) async throws {
        try await withKnownIssue("Sometimes failed to build due to a possible path issue", isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                _ = try await self.build(
                    [],
                    packagePath: fixturePath,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )

                let mainOFile = fixturePath.appending(outputFile)
                let initialMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date

                _ = try await self.build(
                    ["--verbose"],
                    packagePath: fixturePath,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )

                let subsequentMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date
                #expect(initialMainOMtime == subsequentMainOMtime, "Expected no rebuild to occur when using the verbose flag, but the file was modified.")
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(arguments: try buildSystemAndOutputLocation())
    func doesNotRebuildWithSwiftcArgsThatDontAffectIncrementalBuilds(
        buildSystem: BuildSystemProvider.Kind,
        outputFile: Basics.RelativePath
    ) async throws {
        try await withKnownIssue("Sometimes failed to build due to a possible path issue", isIntermittent: true) {
            try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
                _ = try await self.build(
                    [],
                    packagePath: fixturePath,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )

                let mainOFile = fixturePath.appending(outputFile)
                let initialMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date

                _ = try await self.build(
                    ["-Xswiftc", "-diagnostic-style=llvm"],
                    packagePath: fixturePath,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )

                let subsequentMainOMtime = try FileManager.default.attributesOfItem(atPath: mainOFile.pathString)[.modificationDate] as? Date
                #expect(initialMainOMtime == subsequentMainOMtime, "Expected no rebuild to occur when supplying -diagnostic-style, but the file was modified.")
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
        .tags(
            Tag.Feature.CodeCoverage,
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func executingTestsWithCoverageWithoutCodeBuiltWithCoverageGeneratesAFailure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue(isIntermittent: (ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild)) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
                _ = try await self.build(
                    ["--build-tests"],
                    packagePath: path,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
                await #expect(throws: (any Error).self ) {
                    try await executeSwiftTest(
                        path,
                        extraArgs: [
                            "--skip-build",
                            "--enable-code-coverage",
                        ],
                        throwIfCommandFails: true,
                        buildSystem: buildSystem,
                    )
                }
            }
        } when: {
            buildSystem == .xcode || (buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
        .tags(
            Tag.Feature.CodeCoverage,
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func executingTestsWithCoverageWithCodeBuiltWithCoverageGeneratesCodecove(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        // Test that enabling code coverage during building produces the expected folder.
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
                let buildResult = try await self.build(
                    ["--build-tests", "--enable-code-coverage"],
                    packagePath: path,
                    cleanAfterward: false,
                    buildSystem: buildSystem,
                )
                try await executeSwiftTest(
                    path,
                    extraArgs: [
                        "--skip-build",
                        "--enable-code-coverage",
                    ],
                    throwIfCommandFails: true,
                    buildSystem: buildSystem,
                )
                let codeCovPath = buildResult.binPath.appending("codecov")
                let codeCovFiles = try localFileSystem.getDirectoryContents(codeCovPath)
                #expect(codeCovFiles.count > 0)
            }
        } when: {
            [.swiftbuild, .xcode].contains(buildSystem)
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func fatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let expected = 0
        try await fixture(name: "Miscellaneous/Errors/FatalErrorInSingleXCTest/TypeLibrary") { fixturePath in
            // WHEN swift-build --build-tests is executed"
            let error = await #expect(throws: SwiftPMError.self ) {
                try await self.execute(
                    ["--build-tests"],
                    packagePath: fixturePath,buildSystem: buildSystem,
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
         .bug("https://github.com/swiftlang/swift-package-manager/issues/8844"),
         arguments: SupportedBuildSystemOnPlatform,  BuildConfiguration.allCases
     )
     func swiftBuildQuietLogLevel(
         buildSystem: BuildSystemProvider.Kind,
         configuration: BuildConfiguration
     ) async throws {
         try await withKnownIssue {
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
             buildSystem == .swiftbuild && (
                ProcessInfo.hostOperatingSystem == .windows || (
                    ProcessInfo.hostOperatingSystem == .linux && configuration == .release
                )
            )
         }
    }

    @Test(
         .bug("https://github.com/swiftlang/swift-package-manager/issues/8844"),
         arguments: SupportedBuildSystemOnPlatform,  BuildConfiguration.allCases
     )
     func swiftBuildQuietLogLevelWithError(
         buildSystem: BuildSystemProvider.Kind,
         configuration: BuildConfiguration
     ) async throws {
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
                    configuration: .debug,
                    extraArgs: ["--quiet"],
                    buildSystem: buildSystem
                 )
             }

             guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                 Issue.record("Incorrect error was raised.")
                 return
             }

             if buildSystem == .swiftbuild {
                 // THEN we should see output in stderr
                 #expect(stderr.isEmpty == false)
                 // AND no content in stdout
                 #expect(stdout.isEmpty)
             } else {
                 // THEN we should see content in stdout
                 #expect(stdout.isEmpty == false)
                 // AND no output in stderr
                 #expect(stderr.isEmpty)
             }
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



