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

@testable import Commands
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

struct BuildResult {
    let binPath: AbsolutePath
    let output: String
    let binContents: [String]
}

final class BuildToolTests: CommandsTestCase {
    @discardableResult
    private func execute(
        _ args: [String],
        environment: [String : String]? = nil,
        packagePath: AbsolutePath? = nil
    ) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath, env: environment)
    }

    func build(_ args: [String], packagePath: AbsolutePath? = nil) throws -> BuildResult {
        let (output, _) = try execute(args, packagePath: packagePath)
        defer { try! SwiftPMProduct.SwiftPackage.execute(["clean"], packagePath: packagePath) }
        let (binPathOutput, _) = try execute(["--show-bin-path"], packagePath: packagePath)
        let binPath = try AbsolutePath(validating: binPathOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        let binContents = try localFileSystem.getDirectoryContents(binPath)
        return BuildResult(binPath: binPath, output: output, binContents: binContents)
    }
    
    func testUsage() throws {
        let stdout = try execute(["-help"]).stdout
        XCTAssertMatch(stdout, .contains("USAGE: swift build"))
    }

    func testSeeAlso() throws {
        let stdout = try execute(["--help"]).stdout
        XCTAssertMatch(stdout, .contains("SEE ALSO: swift run, swift package, swift test"))
    }

    func testVersion() throws {
        let stdout = try execute(["--version"]).stdout
        XCTAssertMatch(stdout, .contains("Swift Package Manager"))
    }

    func testCreatingSanitizers() throws {
        for sanitizer in Sanitizer.allCases {
            XCTAssertEqual(sanitizer, Sanitizer(argument: sanitizer.shortName))
        }
    }

    func testInvalidSanitizer() throws {
        XCTAssertNil(Sanitizer(argument: "invalid"))
    }

    func testImportOfMissedDepWarning() throws {
        // Verify the warning flow
        try fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            XCTAssertThrowsError(try build(["--explicit-target-dependency-import-check=warn"], packagePath: fullPath)) { error in
                guard case SwiftPMProductError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }

                XCTAssertTrue(stderr.contains("warning: Target A imports another target (B) in the package without declaring it a dependency."))
            }
        }

        // Verify the error flow
        try fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            XCTAssertThrowsError(try build(["--explicit-target-dependency-import-check=error"], packagePath: fullPath)) { error in
                guard case SwiftPMProductError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }

                XCTAssertTrue(stderr.contains("error: Target A imports another target (B) in the package without declaring it a dependency."))
            }
        }

        // Verify that the default does not run the check
        try fixture(name: "Miscellaneous/ImportOfMissingDependency") { path in
            let fullPath = try resolveSymlinks(path)
            XCTAssertThrowsError(try build([], packagePath: fullPath)) { error in
                guard case SwiftPMProductError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }
                XCTAssertFalse(stderr.contains("warning: Target A imports another target (B) in the package without declaring it a dependency."))
            }
        }
    }

    func testBinPathAndSymlink() throws {
        try fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)
            let targetPath = fullPath.appending(components: ".build", try UserToolchain.default.triple.platformBuildPathComponent())
            let xcbuildTargetPath = fullPath.appending(components: ".build", "apple")
            XCTAssertEqual(try execute(["--show-bin-path"], packagePath: fullPath).stdout,
                           "\(targetPath.appending("debug").pathString)\n")
            XCTAssertEqual(try execute(["-c", "release", "--show-bin-path"], packagePath: fullPath).stdout,
                           "\(targetPath.appending("release").pathString)\n")

            // Print correct path when building with XCBuild.
            let xcodeDebugOutput = try execute(["--build-system", "xcode", "--show-bin-path"], packagePath: fullPath).stdout
            let xcodeReleaseOutput = try execute(["--build-system", "xcode", "-c", "release", "--show-bin-path"], packagePath: fullPath).stdout
          #if os(macOS)
            XCTAssertEqual(xcodeDebugOutput, "\(xcbuildTargetPath.appending(components: "Products", "Debug").pathString)\n")
            XCTAssertEqual(xcodeReleaseOutput, "\(xcbuildTargetPath.appending(components: "Products", "Release").pathString)\n")
          #else
            XCTAssertEqual(xcodeDebugOutput, "\(targetPath.appending("debug").pathString)\n")
            XCTAssertEqual(xcodeReleaseOutput, "\(targetPath.appending("release").pathString)\n")
          #endif

            // Test symlink.
            _ = try execute([], packagePath: fullPath)
            XCTAssertEqual(try resolveSymlinks(fullPath.appending(components: ".build", "debug")),
                           targetPath.appending("debug"))
            _ = try execute(["-c", "release"], packagePath: fullPath)
            XCTAssertEqual(try resolveSymlinks(fullPath.appending(components: ".build", "release")),
                           targetPath.appending("release"))
        }
    }

    func testProductAndTarget() throws {
        try fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)

            do {
                let result = try build(["--product", "exec1"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["exec1"])
                XCTAssertNoMatch(result.binContents, ["exec2.build"])
            }

            do {
                let (_, stderr) = try execute(["--product", "lib1"], packagePath: fullPath)
                try SwiftPMProduct.SwiftPackage.execute(["clean"], packagePath: fullPath)
                XCTAssertMatch(stderr, .contains("'--product' cannot be used with the automatic product 'lib1'; building the default target instead"))
            }

            do {
                let result = try build(["--target", "exec2"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["exec2.build"])
                XCTAssertNoMatch(result.binContents, ["exec1"])
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--product", "exec1", "--target", "exec2"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--product' and '--target' are mutually exclusive"))
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--product", "exec1", "--build-tests"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--product' and '--build-tests' are mutually exclusive"))
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--build-tests", "--target", "exec2"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--target' and '--build-tests' are mutually exclusive"))
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--build-tests", "--target", "exec2", "--product", "exec1"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--product', '--target', and '--build-tests' are mutually exclusive"))
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--product", "UnkownProduct"], packagePath: fixturePath)){ error in
                XCTAssertMatch(error.stderr, .contains("error: no product named 'UnkownProduct'"))
            }

            XCTAssertThrowsCommandExecutionError(try execute(["--target", "UnkownTarget"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: no target named 'UnkownTarget'"))
            }
        }
    }
    
    // disabled due to intermittant failures rdar://107759919
    /*
    func testAtMainSupport() throws {
        try fixture(name: "Miscellaneous/AtMainSupport") { fixturePath in
            let fullPath = try resolveSymlinks(fixturePath)

            do {
                let result = try build(["--product", "ClangExecSingleFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["ClangExecSingleFile"])
            }

            do {
                let result = try build(["--product", "SwiftExecSingleFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["SwiftExecSingleFile"])
            }

            do {
                let result = try build(["--product", "SwiftExecMultiFile"], packagePath: fullPath)
                XCTAssertMatch(result.binContents, ["SwiftExecMultiFile"])
            }
        }
    }
    */

    func testNonReachableProductsAndTargetsFunctional() throws {
        try fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
            let aPath = fixturePath.appending("A")

            do {
                let result = try build([], packagePath: aPath)
                XCTAssertNoMatch(result.binContents, ["bexec"])
                XCTAssertNoMatch(result.binContents, ["BTarget2.build"])
                XCTAssertNoMatch(result.binContents, ["cexec"])
                XCTAssertNoMatch(result.binContents, ["CTarget.build"])
            }

            // Dependency contains a dependent product

            do {
                let result = try build(["--product", "bexec"], packagePath: aPath)
                XCTAssertMatch(result.binContents, ["BTarget2.build"])
                XCTAssertMatch(result.binContents, ["bexec"])
                XCTAssertNoMatch(result.binContents, ["aexec"])
                XCTAssertNoMatch(result.binContents, ["ATarget.build"])
                XCTAssertNoMatch(result.binContents, ["BLibrary.a"])

                // FIXME: We create the modulemap during build planning, hence this uglyness.
                let bTargetBuildDir = ((try? localFileSystem.getDirectoryContents(result.binPath.appending("BTarget1.build"))) ?? []).filter{ $0 != moduleMapFilename }
                XCTAssertTrue(bTargetBuildDir.isEmpty, "bTargetBuildDir should be empty")

                XCTAssertNoMatch(result.binContents, ["cexec"])
                XCTAssertNoMatch(result.binContents, ["CTarget.build"])

                // Also make sure we didn't emit parseable module interfaces
                // (do this here to avoid doing a second build in
                // testParseableInterfaces().
                XCTAssertNoMatch(result.binContents, ["ATarget.swiftinterface"])
                XCTAssertNoMatch(result.binContents, ["BTarget.swiftinterface"])
                XCTAssertNoMatch(result.binContents, ["CTarget.swiftinterface"])
            }
        }
    }

    func testParseableInterfaces() throws {
        try fixture(name: "Miscellaneous/ParseableInterfaces") { fixturePath in
            do {
                let result = try build(["--enable-parseable-module-interfaces"], packagePath: fixturePath)
                XCTAssertMatch(result.binContents, ["A.swiftinterface"])
                XCTAssertMatch(result.binContents, ["B.swiftinterface"])
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }
        }
    }

    func testAutomaticParseableInterfacesWithLibraryEvolution() throws {
        try fixture(name: "Miscellaneous/LibraryEvolution") { fixturePath in
            do {
                let result = try build([], packagePath: fixturePath)
                XCTAssertMatch(result.binContents, ["A.swiftinterface"])
                XCTAssertMatch(result.binContents, ["B.swiftinterface"])
            }
        }
    }

    func testBuildCompleteMessage() throws {
        throw XCTSkip("This test fails to match the 'Compiling' regex; rdar://101815761")

        try fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            do {
                let result = try execute([], packagePath: fixturePath)
                XCTAssertMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                let lines = result.stdout.split(separator: "\n")
                XCTAssertMatch(String(lines.last!), .regex("Build complete! \\([0-9]*\\.[0-9]*s\\)"))
            }

            do {
                // test second time, to stabilize the cache
                let _ = try execute([], packagePath: fixturePath)
            }

            do {
                // test third time, to make sure message is presented even when nothing to build (cached)
                let result = try execute([], packagePath: fixturePath)
                XCTAssertNoMatch(result.stdout, .regex("\\[[1-9][0-9]*\\/[1-9][0-9]*\\] Compiling"))
                let lines = result.stdout.split(separator: "\n")
                XCTAssertMatch(String(lines.last!), .regex("Build complete! \\([0-9]*\\.[0-9]*s\\)"))
            }
        }
    }

    func testBuildStartMessage() throws {
        try fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            do {
                let result = try execute(["-c", "debug"], packagePath: fixturePath)
                XCTAssertMatch(result.stdout, .prefix("Building for debugging"))
            }

            do {
                let result = try execute(["-c", "release"], packagePath: fixturePath)
                XCTAssertMatch(result.stdout, .prefix("Building for production"))
            }
        }
    }

    func testXcodeBuildSystemDefaultSettings() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test requires `xcbuild` and is therefore only supported on macOS")
        #endif
        try fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            // Try building using XCBuild with default parameters.  This should succeed.  We build verbosely so we get full command lines.
            let defaultOutput = try execute(["-c", "debug", "-v"], packagePath: fixturePath).stdout
            
            // Look for certain things in the output from XCBuild.
            XCTAssertMatch(defaultOutput, .contains("-target \(try UserToolchain.default.triple.tripleString(forPlatformVersion: ""))"))
        }
    }

    func testXcodeBuildSystemWithAdditionalBuildFlags() throws {
        try XCTSkipIf(true, "Disabled for now because it is hitting 'IR generation failure: Cannot read legacy layout file' in CI (rdar://88828632)")

        #if !os(macOS)
        try XCTSkipIf(true, "test requires `xcbuild` and is therefore only supported on macOS")
        #endif
        try fixture(name: "ValidLayouts/SingleModule/ExecutableMixed") { fixturePath in
            // Try building using XCBuild with additional flags.  This should succeed.  We build verbosely so we get full command lines.
            let defaultOutput = try execute(
                [
                    "--build-system", "xcode",
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

    func testXcodeBuildSystemOverrides() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test requires `xcbuild` and is therefore only supported on macOS")
        #endif
        try fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            // Try building using XCBuild without specifying overrides.  This should succeed, and should use the default compiler path.
            let defaultOutput = try execute(["-c", "debug", "--vv"], packagePath: fixturePath).stdout
            XCTAssertMatch(defaultOutput, .contains(try UserToolchain.default.swiftCompilerPath.pathString))

            // Now try building using XCBuild while specifying a faulty compiler override.  This should fail.  Note that we need to set the executable to use for the manifest itself to the default one, since it defaults to SWIFT_EXEC if not provided.
            var overriddenOutput = ""
            XCTAssertThrowsCommandExecutionError(
                try execute(
                    ["-c", "debug", "--vv"],
                    environment: ["SWIFT_EXEC": "/usr/bin/false", "SWIFT_EXEC_MANIFEST": UserToolchain.default.swiftCompilerPath.pathString],
                    packagePath: fixturePath
                )
            ) { error in
                overriddenOutput = error.stderr
            }
            XCTAssertMatch(overriddenOutput, .contains("/usr/bin/false"))
        }
    }

    func testPrintLLBuildManifestJobGraph() throws {
        try fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            let output = try execute(["--print-manifest-job-graph"], packagePath: fixturePath).stdout
            XCTAssertMatch(output, .prefix("digraph Jobs {"))
        }
    }
    
    func testSwiftDriverRawOutputGetsNewlines() throws {
        try fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
            // Building with `-wmo` should result in a `remark: Incremental compilation has been disabled: it is not compatible with whole module optimization` message, which should have a trailing newline.  Since that message won't be there at all when the legacy compiler driver is used, we gate this check on whether the remark is there in the first place.
            let result = try execute(["-c", "release", "-Xswiftc", "-wmo"], packagePath: fixturePath)
            if result.stdout.contains("remark: Incremental compilation has been disabled: it is not compatible with whole module optimization") {
                XCTAssertMatch(result.stdout, .contains("optimization\n"))
                XCTAssertNoMatch(result.stdout, .contains("optimization["))
                XCTAssertNoMatch(result.stdout, .contains("optimizationremark"))
            }
        }
    }
}
