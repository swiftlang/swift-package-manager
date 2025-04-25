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
import SPMBuildCore
import _InternalTestSupport
import TSCTestSupport
import Workspace
import XCTest

struct BuildResult {
    let binPath: AbsolutePath
    let stdout: String
    let stderr: String
    let binContents: [String]
    let moduleContents: [String]
}

class BuildCommandTestCases: CommandsBuildProviderTestCase {

    override func setUpWithError() throws {
        try XCTSkipIf(type(of: self) == BuildCommandTestCases.self, "Skipping this test since it will be run in subclasses that will provide different build systems to test.")
    }

    @discardableResult
    func execute(
        _ args: [String] = [],
        environment: Environment? = nil,
        packagePath: AbsolutePath? = nil
    ) async throws -> (stdout: String, stderr: String) {
        return try await executeSwiftBuild(
            packagePath,
            extraArgs: args,
            env: environment,
            buildSystem: buildSystemProvider
        )
    }

    func build(_ args: [String], packagePath: AbsolutePath? = nil, isRelease: Bool = false, cleanAfterward: Bool = true) async throws -> BuildResult {
        do {
            let buildConfigurationArguments = isRelease ? ["-c", "release"] : []
            let (stdout, stderr) = try await execute(args + buildConfigurationArguments, packagePath: packagePath)
            defer {
            }
            let (binPathOutput, _) = try await execute(
                ["--show-bin-path"] + buildConfigurationArguments,
                packagePath: packagePath
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
            if buildSystemProvider == .native { 
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
                try! await executeSwiftPackage(
                    packagePath,
                    extraArgs: ["clean"],
                    buildSystem: buildSystemProvider
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
                try! await executeSwiftPackage(
                    packagePath,
                    extraArgs: ["clean"],
                    buildSystem: buildSystemProvider
                )
            }
            throw error
        }
    }

    func testUsage() async throws {
        let stdout = try await execute(["-help"]).stdout
        XCTAssertMatch(stdout, .contains("USAGE: swift build"))
    }

    func testBinSymlink() async throws {
        XCTAssertTrue(false, "Must be implemented at build system test class.")
    }

    func testSeeAlso() async throws {
        let stdout = try await execute(["--help"]).stdout
        XCTAssertMatch(stdout, .contains("SEE ALSO: swift run, swift package, swift test"))
    }

    func testCommandDoesNotEmitDuplicateSymbols() async throws {
        let (stdout, stderr) = try await SwiftPM.Build.execute(["--help"])
        XCTAssertNoMatch(stdout, duplicateSymbolRegex)
        XCTAssertNoMatch(stderr, duplicateSymbolRegex)
    }

    func testVersion() async throws {
        let stdout = try await execute(["--version"]).stdout
        XCTAssertMatch(stdout, .regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#))
    }

    func testCreatingSanitizers() throws {
        for sanitizer in Sanitizer.allCases {
            XCTAssertEqual(sanitizer, Sanitizer(argument: sanitizer.shortName))
        }
    }

    func testInvalidSanitizer() throws {
        XCTAssertNil(Sanitizer(argument: "invalid"))
    }

    func testImportOfMissedDepWarning() async throws {
        // Verify the warning flow
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            await XCTAssertAsyncThrowsError(try await self.build(
                ["--explicit-target-dependency-import-check=warn"],
                packagePath: fullPath
            )) { error in
                guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                    XCTFail()
                    return
                }

                XCTAssertTrue(
                    stderr.contains(
                        "warning: Target A imports another target (B) in the package without declaring it a dependency."
                    ),
                    "got stdout: \(stdout), stderr: \(stderr)"
                )
            }
        }

        // Verify the error flow
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            await XCTAssertAsyncThrowsError(try await self.build(
                ["--explicit-target-dependency-import-check=error"],
                packagePath: fullPath
            )) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }

                XCTAssertTrue(
                    stderr.contains(
                        "error: Target A imports another target (B) in the package without declaring it a dependency."
                    ),
                    "got stdout: \(String(describing: stdout)), stderr: \(String(describing: stderr))"
                )
            }
        }

        // Verify that the default does not run the check
        try await fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            await XCTAssertAsyncThrowsError(try await self.build([], packagePath: fullPath)) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }
                XCTAssertFalse(
                    stderr.contains(
                        "warning: Target A imports another target (B) in the package without declaring it a dependency."
                    ),
                    "got stdout: \(String(describing: stdout)), stderr: \(String(describing: stderr))"
                )
            }
        }
    }

    func testSymlink() async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)
            let targetPath = try fullPath.appending(components:
                ".build",
                UserToolchain.default.targetTriple.platformBuildPathComponent
            )
            // Test symlink.
            try await self.execute(packagePath: fullPath)
            XCTAssertEqual(
                try resolveSymlinks(fullPath.appending(components: ".build", "debug")),
                targetPath.appending("debug")
            )
            try await self.execute(["-c", "release"], packagePath: fullPath)
            XCTAssertEqual(
                try resolveSymlinks(fullPath.appending(components: ".build", "release")),
                targetPath.appending("release")
            )
        }
    }

    func testProductAndTarget() async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)

            do {
                let result = try await build(["--product", "exec1"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["exec1"])
                XCTAssertNoMatch(result.binContents, ["exec2.build"])
            }

            do {
                let (_, stderr) = try await execute(["--product", "lib1"], packagePath: fullPath)
                try await executeSwiftPackage(
                    fullPath,
                    extraArgs:["clean"],
                    buildSystem: buildSystemProvider
                )
                XCTAssertMatch(
                    stderr,
                    .contains(
                        "'--product' cannot be used with the automatic product 'lib1'; building the default target instead"
                    )
                )
            }

            do {
                let result = try await build(["--target", "exec2"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["exec2.build"])
                XCTAssertNoMatch(result.binContents, ["exec1"])
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--product", "exec1", "--target", "exec2"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--product' and '--target' are mutually exclusive"))
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--product", "exec1", "--build-tests"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--product' and '--build-tests' are mutually exclusive"))
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--build-tests", "--target", "exec2"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--target' and '--build-tests' are mutually exclusive"))
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--build-tests", "--target", "exec2", "--product", "exec1"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(
                    error.stderr,
                    .contains("error: '--product', '--target', and '--build-tests' are mutually exclusive")
                )
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--product", "UnkownProduct"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(error.stderr, .contains("error: no product named 'UnkownProduct'"))
            }

            await XCTAssertThrowsCommandExecutionError(try await self.execute(
                ["--target", "UnkownTarget"],
                packagePath: fixturePath
            )) { error in
                XCTAssertMatch(error.stderr, .contains("error: no target named 'UnkownTarget'"))
            }
        }
    }

    func testAtMainSupport() async throws {
        try await fixture(name: "Miscellaneous/AtMainSupport") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)

            do {
                let result = try await build(["--product", "ClangExecSingleFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["ClangExecSingleFile"])
            }

            do {
                let result = try await build(["--product", "SwiftExecSingleFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["SwiftExecSingleFile"])
            }

            do {
                let result = try await build(["--product", "SwiftExecMultiFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["SwiftExecMultiFile"])
            }
        }
    }

    func testNonReachableProductsAndTargetsFunctional() async throws {
        try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
            let aPath = fixturePath.appending("A")

            do {
                let result = try await build([], packagePath: aPath)
                XCTAssertNoMatch(result.binContents, ["bexec"])
                XCTAssertNoMatch(result.binContents, ["BTarget2.build"])
                XCTAssertNoMatch(result.binContents, ["cexec"])
                XCTAssertNoMatch(result.binContents, ["CTarget.build"])
            }

            // Dependency contains a dependent product

            do {
                let result = try await build(["--product", "bexec"], packagePath: aPath)
                XCTAssertMatch(result.binContents, ["BTarget2.build"])
                XCTAssertMatch(result.binContents, ["bexec"])
                XCTAssertNoMatch(result.binContents, ["aexec"])
                XCTAssertNoMatch(result.binContents, ["ATarget.build"])
                XCTAssertNoMatch(result.binContents, ["BLibrary.a"])

                // FIXME: We create the modulemap during build planning, hence this ugliness.
                let bTargetBuildDir =
                    ((try? localFileSystem.getDirectoryContents(result.binPath.appending("BTarget1.build"))) ?? [])
                        .filter { $0 != moduleMapFilename }
                XCTAssertTrue(bTargetBuildDir.isEmpty, "bTargetBuildDir should be empty")

                XCTAssertNoMatch(result.binContents, ["cexec"])
                XCTAssertNoMatch(result.binContents, ["CTarget.build"])

                // Also make sure we didn't emit parseable module interfaces
                // (do this here to avoid doing a second build in
                // testParseableInterfaces().
                XCTAssertNoMatch(result.moduleContents, ["ATarget.swiftinterface"])
                XCTAssertNoMatch(result.moduleContents, ["BTarget.swiftinterface"])
                XCTAssertNoMatch(result.moduleContents, ["CTarget.swiftinterface"])
            }
        }
    }

    func testParseableInterfaces() async throws {
        try await fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            do {
                let result = try await build(["--enable-parseable-module-interfaces"], packagePath: fixturePath)
                XCTAssertMatch(result.moduleContents, ["A.swiftinterface"])
                XCTAssertMatch(result.moduleContents, ["B.swiftinterface"])
            } catch SwiftPMError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }
        }
    }

    func testAutomaticParseableInterfacesWithLibraryEvolution() async throws {
        try await fixture(name: "Miscellaneous/LibraryEvolution") { fixturePath in
            do {
                let result = try await build([], packagePath: fixturePath)
                XCTAssertMatch(result.moduleContents, ["A.swiftinterface"])
                XCTAssertMatch(result.moduleContents, ["B.swiftinterface"])
            }
        }
    }

    func testBuildCompleteMessage() async throws {
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            do {
                let result = try await execute(packagePath: fixturePath)
                // This test fails to match the 'Compiling' regex; rdar://101815761
                // XCTAssertMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                XCTAssertMatch(String(lines.last!), .regex("Build complete! \\([0-9]*\\.[0-9]*\\s*s(econds)?\\)"))
            }

            do {
                // test second time, to stabilize the cache
                try await self.execute(packagePath: fixturePath)
            }

            do {
                // test third time, to make sure message is presented even when nothing to build (cached)
                let result = try await execute(packagePath: fixturePath)
                // This test fails to match the 'Compiling' regex; rdar://101815761
                // XCTAssertNoMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                let lines = result.stdout.split(whereSeparator: { $0.isNewline })
                XCTAssertMatch(String(lines.last!), .regex("Build complete! \\([0-9]*\\.[0-9]*\\s*s(econds)?\\)"))
            }
        }
    }

    func testBuildStartMessage() async throws {
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            do {
                let result = try await execute(["-c", "debug"], packagePath: fixturePath)
                XCTAssertMatch(result.stdout, .prefix("Building for debugging"))
            }

            do {
                let result = try await execute(["-c", "release"], packagePath: fixturePath)
                XCTAssertMatch(result.stdout, .prefix("Building for production"))
            }
        }
    }

    func testBuildSystemDefaultSettings() async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            // try await building using XCBuild with default parameters.  This should succeed.  We build verbosely so we get
            // full command lines.
            let output = try await execute(["-c", "debug", "-v"], packagePath: fixturePath)

            // In the case of the native build system check for the cross-compile target, only for macOS
#if os(macOS)
            if buildSystemProvider == .native {
                 XCTAssertMatch(
                     output.stdout,
                     try .contains("-target \(UserToolchain.default.targetTriple.tripleString(forPlatformVersion: ""))")
                 )
            }
#endif

            // Look for build completion message from the particular build system
            XCTAssertMatch(
                output.stdout,
                .contains("Build complete!")
            )
        }
    }

    func testXcodeBuildSystemWithAdditionalBuildFlags() async throws {
        try XCTSkipIf(
            true,
            "Disabled for now because it is hitting 'IR generation failure: Cannot read legacy layout file' in CI (rdar://88828632)"
        )

        guard buildSystemProvider == .xcode || buildSystemProvider == .swiftbuild else {
            throw XCTSkip("This test only works with the xcode or swift build build system")
        }

        try await fixture(name: "ValidLayouts/SingleModule/ExecutableMixed") { fixturePath in
            // try await building using XCBuild with additional flags.  This should succeed.  We build verbosely so we get
            // full command lines.
            let defaultOutput = try await execute(
                [
                    "-c", "debug", "-v",
                    "-Xlinker", "-rpath", "-Xlinker", "/fakerpath",
                    "-Xcc", "-I/cfakepath",
                    "-Xcxx", "-I/cxxfakepath",
                    "-Xswiftc", "-I/swiftfakepath",
                ],
                packagePath: fixturePath
            ).stdout

            // Look for certain things in the output from XCBuild.
            XCTAssertMatch(defaultOutput, .contains("/fakerpath"))
            XCTAssertMatch(defaultOutput, .contains("-I/cfakepath"))
            XCTAssertMatch(defaultOutput, .contains("-I/cxxfakepath"))
            XCTAssertMatch(defaultOutput, .contains("-I/swiftfakepath"))
        }
    }

    func testBuildSystemOverrides() async throws {
        guard buildSystemProvider == .xcode else {
            throw XCTSkip("Build system overrides are only available with the xcode build system.")
        }

        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            // try await building using XCBuild without specifying overrides.  This should succeed, and should use the default
            // compiler path.
            let defaultOutput = try await execute(["-c", "debug", "--vv"], packagePath: fixturePath).stdout
            XCTAssertMatch(defaultOutput, try .contains(UserToolchain.default.swiftCompilerPath.pathString))

            // Now try await building using XCBuild while specifying a faulty compiler override.  This should fail.  Note that
            // we need to set the executable to use for the manifest itself to the default one, since it defaults to
            // SWIFT_EXEC if not provided.
            var overriddenOutput = ""
            await XCTAssertThrowsCommandExecutionError(
                try await self.execute(
                    ["-c", "debug", "--vv"],
                    environment: [
                        "SWIFT_EXEC": "/usr/bin/false",
                        "SWIFT_EXEC_MANIFEST": UserToolchain.default.swiftCompilerPath.pathString,
                    ],
                    packagePath: fixturePath
                )
            ) { error in
                overriddenOutput = error.stderr
            }
            XCTAssertMatch(overriddenOutput, .contains("/usr/bin/false"))
        }
    }

    func testPrintLLBuildManifestJobGraph() async throws {
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let output = try await execute(["--print-manifest-job-graph"], packagePath: fixturePath).stdout
            XCTAssertMatch(output, .prefix("digraph Jobs {"))
        }
    }

    func testSwiftDriverRawOutputGetsNewlines() async throws {
        try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            // Building with `-wmo` should result in a `remark: Incremental compilation has been disabled: it is not
            // compatible with whole module optimization` message, which should have a trailing newline.  Since that
            // message won't be there at all when the legacy compiler driver is used, we gate this check on whether the
            // remark is there in the first place.
            let result = try await execute(["-c", "release", "-Xswiftc", "-wmo"], packagePath: fixturePath)
            if result.stdout.contains(
                "remark: Incremental compilation has been disabled: it is not compatible with whole module optimization"
            ) {
                XCTAssertMatch(result.stdout, .contains("optimization\n"))
                XCTAssertNoMatch(result.stdout, .contains("optimization["))
                XCTAssertNoMatch(result.stdout, .contains("optimizationremark"))
            }
        }
    }

    func testSwiftGetVersion() async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            func findSwiftGetVersionFile() throws -> AbsolutePath {
                let buildArenaPath = fixturePath.appending(components: ".build", "debug")
                let files = try localFileSystem.getDirectoryContents(buildArenaPath)
                let filename = try XCTUnwrap(files.first { $0.hasPrefix("swift-version") })
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

            // Build with a swiftc that returns version 1.0, we expect a successful build which compiles our one source
            // file.
            do {
                let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath)
                XCTAssertTrue(
                    result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                    "compilation task missing from build result: \(result.stdout)"
                )
                XCTAssertTrue(result.stdout.contains("Build complete!"), "unexpected build result: \(result.stdout)")
                let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                XCTAssertEqual(try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp(), "1.0")
            }

            // Build again with that same version, we do not expect any compilation tasks.
            do {
                let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath)
                XCTAssertFalse(
                    result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                    "compilation task present in build result: \(result.stdout)"
                )
                XCTAssertTrue(result.stdout.contains("Build complete!"), "unexpected build result: \(result.stdout)")
                let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                XCTAssertEqual(try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp(), "1.0")
            }

            // Build again with a swiftc that returns version 2.0, we expect compilation happening once more.
            do {
                environment["CUSTOM_SWIFT_VERSION"] = "2.0"
                let result = try await execute(["--verbose"], environment: environment, packagePath: fixturePath)
                XCTAssertTrue(
                    result.stdout.contains("\(dummySwiftcPath.pathString) -module-name"),
                    "compilation task missing from build result: \(result.stdout)"
                )
                XCTAssertTrue(result.stdout.contains("Build complete!"), "unexpected build result: \(result.stdout)")
                let swiftGetVersionFilePath = try findSwiftGetVersionFile()
                XCTAssertEqual(try String(contentsOfFile: swiftGetVersionFilePath.pathString).spm_chomp(), "2.0")
            }
        }
    }

    func testGetTaskAllowEntitlement() async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            #if os(macOS)
            // try await building with default parameters.  This should succeed. We build verbosely so we get full command
            // lines.
            var buildResult = try await build(["-v"], packagePath: fixturePath)

            // TODO verification of the ad-hoc code signing can be done by `swift run` of the executable in these cases once swiftbuild build system is working with that
            XCTAssertMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(["-c", "debug", "-v"], packagePath: fixturePath)

            XCTAssertMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            // Build with different combinations of the entitlement flag and debug/release build configurations.

            buildResult = try await self.build(
                ["--enable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath,
                isRelease: true
            )

            XCTAssertMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(
                ["-c", "debug", "--enable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath
            )

            XCTAssertMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(
                ["-c", "debug", "--disable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath
            )

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(
                ["--disable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath,
                isRelease: true
            )

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))
            #else
            var buildResult = try await self.build(["-v"], packagePath: fixturePath)

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(["-v"], packagePath: fixturePath, isRelease: true)

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))

            buildResult = try await self.build(
                ["--disable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath,
                isRelease: true
            )

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))
            XCTAssertMatch(buildResult.stderr, .contains(SwiftCommandState.entitlementsMacOSWarning))

            buildResult = try await self.build(
                ["--enable-get-task-allow-entitlement", "-v"],
                packagePath: fixturePath,
                isRelease: true
            )

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))
            XCTAssertMatch(buildResult.stderr, .contains(SwiftCommandState.entitlementsMacOSWarning))
            #endif

            buildResult = try await self.build(["-c", "release", "-v"], packagePath: fixturePath, isRelease: true)

            XCTAssertNoMatch(buildResult.stdout, .contains("codesign --force --sign - --entitlements"))
        }
    }

#if !canImport(Darwin)
    func testIgnoresLinuxMain() async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/IgnoresLinuxMain") { fixturePath in
            let buildResult = try await self.build(["-v", "--build-tests", "--enable-test-discovery"], packagePath: fixturePath, cleanAfterward: false)
            let testBinaryPath = buildResult.binPath.appending("IgnoresLinuxMainPackageTests.xctest")

            _ = try await AsyncProcess.checkNonZeroExit(arguments: [testBinaryPath.pathString])
        }
    }
#endif

    func testCodeCoverage() async throws {
        // Test that no codecov directory is created if not specified when building.
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
            _ = try await self.build(["--build-tests"], packagePath: path, cleanAfterward: false)
            await XCTAssertAsyncThrowsError(
                try await executeSwiftTest(
                    path,
                    extraArgs: [
                        "--skip-build",
                        "--enable-code-coverage",
                    ],
                    throwIfCommandFails: true,
                    buildSystem: buildSystemProvider
                )
            )
        }

        // Test that enabling code coverage during building produces the expected folder.
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
            let buildResult = try await self.build(["--build-tests", "--enable-code-coverage"], packagePath: path, cleanAfterward: false)
            try await executeSwiftTest(
                path,
                extraArgs: [
                    "--skip-build",
                    "--enable-code-coverage",
                ],
                throwIfCommandFails: true,
                buildSystem: buildSystemProvider
            )
            let codeCovPath = buildResult.binPath.appending("codecov")
            let codeCovFiles = try localFileSystem.getDirectoryContents(codeCovPath)
            XCTAssertGreaterThan(codeCovFiles.count, 0)
        }
    }

    func testFatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation() async throws {
        let expected = 0
        try await fixture(name: "Miscellaneous/Errors/FatalErrorInSingleXCTest/TypeLibrary") { fixturePath in
            // WHEN swift-build --build-tests is executed"
            await XCTAssertAsyncThrowsError(try await self.execute(["--build-tests"], packagePath: fixturePath)) { error in
                // THEN I expect a failure
                guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                    XCTFail("Building the package was expected to fail, but it was successful")
                    return
                }

                let matchString = "error: fatalError"
                let stdoutMatches = getNumberOfMatches(of: matchString, in: stdout)
                let stderrMatches = getNumberOfMatches(of: matchString, in: stderr)
                let actualNumMatches = stdoutMatches + stderrMatches

                // AND a fatal error message is printed \(expected) times
                XCTAssertEqual(
                    actualNumMatches,
                    expected,
                    [
                        "Actual (\(actualNumMatches)) is not as expected (\(expected))",
                        "stdout: \(stdout.debugDescription)",
                        "stderr: \(stderr.debugDescription)"
                    ].joined(separator: "\n")
                )
            }
        }
    }

}


class BuildCommandNativeTests: BuildCommandTestCases {

    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .native
    }

    override func testUsage() async throws {
        try await super.testUsage()
    }

    override func testBinSymlink() async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)
            let targetPath = try fullPath.appending(
                components: ".build",
                UserToolchain.default.targetTriple.platformBuildPathComponent
            )
            try await XCTAssertAsyncEqual(
                try await self.execute(["--show-bin-path"], packagePath: fullPath).stdout,
                "\(targetPath.appending("debug").pathString)\n"
            )
            try await XCTAssertAsyncEqual(
                try await self.execute(["-c", "release", "--show-bin-path"], packagePath: fullPath)
                    .stdout,
                "\(targetPath.appending("release").pathString)\n"
            )
        }
    }
}

#if os(macOS)
// Xcode build system tests can only function on macOS
class BuildCommandXcodeTests: BuildCommandTestCases {
    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .xcode
    }

    override func testUsage() async throws {
        try await super.testUsage()
    }

    override func testAutomaticParseableInterfacesWithLibraryEvolution() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testNonReachableProductsAndTargetsFunctional() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testCodeCoverage() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testBuildStartMessage() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testBinSymlink() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testSymlink() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testSwiftGetVersion() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testParseableInterfaces() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testProductAndTarget() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testImportOfMissedDepWarning() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testGetTaskAllowEntitlement() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }

    override func testBuildCompleteMessage() async throws {
        throw XCTSkip("Test not implemented for xcode build system.")
    }
}
#endif

class BuildCommandSwiftBuildTests: BuildCommandTestCases {

    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .swiftbuild
    }

    override func testNonReachableProductsAndTargetsFunctional() async throws {
        throw XCTSkip("SWBINTTODO: Test failed. This needs to be investigated")
    }

    override func testParseableInterfaces() async throws {
        #if os(Linux)
        if FileManager.default.contents(atPath: "/etc/system-release")
                .map { String(decoding: $0, as: UTF8.self) == "Amazon Linux release 2 (Karoo)\n" } ?? false {
            throw XCTSkip("https://github.com/swiftlang/swift-package-manager/issues/8545: Test currently fails on Amazon Linux 2")
        }
        #endif
        try await fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            do {
                let result = try await build(["--enable-parseable-module-interfaces"], packagePath: fixturePath)
                XCTAssertMatch(result.moduleContents, [.regex(#"A[.]swiftmodule[/].*[.]swiftinterface"#)])
                XCTAssertMatch(result.moduleContents, [.regex(#"B[.]swiftmodule[/].*[.]swiftmodule"#)])
            } catch SwiftPMError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }
        }
    }
    
    override func testAutomaticParseableInterfacesWithLibraryEvolution() async throws {
        throw XCTSkip("SWBINTTODO: Test failed because of missing 'A.swiftmodule/*.swiftinterface' files")
        // TODO: We still need to override this test just like we did for `testParseableInterfaces` above.
    }

    override func testBinSymlink() async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)
            let targetPath = try fullPath.appending(
                components: ".build",
                UserToolchain.default.targetTriple.platformBuildPathComponent
            )
            let debugPath = try await self.execute(["--show-bin-path"], packagePath: fullPath).stdout
            XCTAssertMatch(debugPath, .regex(targetPath.appending(components: "Products", "Debug").pathString + "(\\-linux|\\-Windows)?\\n"))
            let releasePath = try await self.execute(["-c", "release", "--show-bin-path"], packagePath: fullPath).stdout
            XCTAssertMatch(releasePath, .regex(targetPath.appending(components: "Products", "Release").pathString + "(\\-linux|\\-Windows)?\\n"))
        }
    }
    
    override func testGetTaskAllowEntitlement() async throws {
        throw XCTSkip("SWBINTTODO: Test failed because swiftbuild doesn't output precis codesign commands. Once swift run works with swiftbuild the test can be investigated.")
    }

    override func testCodeCoverage() async throws {
        throw XCTSkip("SWBINTTODO: Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there.")
    }

    override func testAtMainSupport() async throws {
        #if !os(macOS)
        throw XCTSkip("SWBINTTODO: File not found or missing libclang errors on non-macOS platforms. This needs to be investigated")
        #else
        try await super.testAtMainSupport()
        #endif
    }

    override func testImportOfMissedDepWarning() async throws {
        throw XCTSkip("SWBINTTODO: Test fails because the warning message regarding missing imports is expected to be more verbose and actionable at the SwiftPM level with mention of the involved targets. This needs to be investigated. See case targetDiagnostic(TargetDiagnosticInfo) as a message type that may help.")
    }

    override func testProductAndTarget() async throws {
        throw XCTSkip("SWBINTTODO: Test fails because there isn't a clear warning message about the lib1 being an automatic product and that the default product is being built instead. This needs to be investigated")
    }

    override func testSwiftGetVersion() async throws {
        throw XCTSkip("SWBINTTODO: Test fails because the dummy-swiftc used in the test isn't accepted by swift-build. This needs to be investigated")
    }

    override func testSymlink() async throws {
        throw XCTSkip("SWBINTTODO: Test fails because of a difference in the build layout. This needs to be updated to the expected path")
    }

#if !canImport(Darwin)
    override func testIgnoresLinuxMain() async throws {
        throw XCTSkip("SWBINTTODO: Swift build doesn't currently ignore Linux main when linking on Linux. This needs further investigation.")
    }
#endif

#if !os(macOS)
    override func testBuildStartMessage() async throws {
        throw XCTSkip("SWBINTTODO: Swift build produces an error building the fixture for this test.")
    }

    override func testSwiftDriverRawOutputGetsNewlines() async throws {
        throw XCTSkip("SWBINTTODO: Swift build produces an error building the fixture for this test.")
    }
#endif

    override func testBuildSystemDefaultSettings() async throws {
        #if os(Linux)
        if FileManager.default.contents(atPath: "/etc/system-release").map( { String(decoding: $0, as: UTF8.self) == "Amazon Linux release 2 (Karoo)\n" } ) ?? false {
            throw XCTSkip("Skipping SwiftBuild testing on Amazon Linux because of platform issues.")
        }
        #endif

        if ProcessInfo.processInfo.environment["SWIFTPM_NO_SWBUILD_DEPENDENCY"] != nil {
            throw XCTSkip("SWIFTPM_NO_SWBUILD_DEPENDENCY is set so skipping because SwiftPM doesn't have the swift-build capability built inside.")
        }

        try await super.testBuildSystemDefaultSettings()
    }

    override func testBuildCompleteMessage() async throws {
        #if os(Linux)
        throw XCTSkip("SWBINTTODO: Need to properly set LD_LIBRARY_PATH on linux")
        #else
        try await super.testBuildCompleteMessage()
        #endif
    }

}
