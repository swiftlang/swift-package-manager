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

import Basics
import PackageModel
import SourceControl
import _InternalTestSupport
import Workspace
import XCTest

import class Basics.AsyncProcess
import enum TSCUtility.Git

typealias ProcessID = AsyncProcess.ProcessID

final class MiscellaneousTestCase: XCTestCase {
    func testPrintsSelectedDependencyVersion() async throws {
        // verifies the stdout contains information about
        // the selected version of the package

        try await fixtureXCTest(name: "DependencyResolution/External/Simple") { fixturePath in
            let (stdout, stderr) = try await executeSwiftBuild(
                fixturePath.appending("Bar"),
                buildSystem: .native,
            )
            // package resolution output goes to stderr
            XCTAssertMatch(stderr, .regex("Computed .* at 1\\.2\\.3"))
            // in "swift build" build output goes to stdout
            XCTAssertMatch(stdout, .contains("Compiling Foo Foo.swift"))
            XCTAssertMatch(stdout, .or(.contains("Merging module Foo"),
                                       .contains("Emitting module Foo")))
            XCTAssertMatch(stdout, .contains("Compiling Bar main.swift"))
            XCTAssertMatch(stdout, .or(.contains("Merging module Bar"),
                                      .contains("Emitting module Bar")))
            XCTAssertMatch(stdout, .contains("Linking Bar"))
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    func testPassExactDependenciesToBuildCommand() async throws {
        // regression test to ensure that dependencies of other dependencies
        // are not passed into the build-command.

        try await fixtureXCTest(name: "Miscellaneous/ExactDependencies") { fixturePath in
            await XCTAssertBuilds(
                fixturePath.appending("app"),
                buildSystem: .native,
            )
            let buildDir = fixturePath.appending(components: "app", ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            XCTAssertFileExists(buildDir.appending(executableName("FooExec")))
            XCTAssertFileExists(buildDir.appending(components: "Modules", "FooLib1.swiftmodule"))
            XCTAssertFileExists(buildDir.appending(components: "Modules", "FooLib2.swiftmodule"))
        }
    }

    func testCanBuildMoreThanTwiceWithExternalDependencies() async throws {
        // running `swift build` multiple times should not fail
        // subsequent executions to an unmodified source tree
        // should immediately exit with exit-status: `0`

        try await fixtureXCTest(name: "DependencyResolution/External/Complex") { fixturePath in
            await XCTAssertBuilds(
                fixturePath.appending("app"),
                buildSystem: .native,
            )
            await XCTAssertBuilds(
                fixturePath.appending("app"),
                buildSystem: .native,
            )
            await XCTAssertBuilds(
                fixturePath.appending("app"),
                buildSystem: .native,
            )
        }
    }

    func testNoArgumentsExitsWithOne() async throws {
        await XCTAssertThrowsCommandExecutionError(
            try await executeSwiftBuild(
                "/",
                buildSystem: .native,
            )
        ) { error in
            // if our code crashes we'll get an exit code of 256
            guard error.result.exitStatus == .terminated(code: 1) else {
                return XCTFail("failed in an unexpected manner: \(error)")
            }
        }
    }

    func testCompileFailureExitsGracefully() async throws {
        try await fixtureXCTest(name: "Miscellaneous/CompileFails") { fixturePath in
            await XCTAssertThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath,
                    buildSystem: .native,
                )
            ) { error in
                // if our code crashes we'll get an exit code of 256
                guard error.result.exitStatus == .terminated(code: 1) else {
                    return XCTFail("failed in an unexpected manner: \(error)")
                }
                XCTAssertMatch(error.stdout + error.stderr, .contains("Compiling CompileFails Foo.swift"))
                XCTAssertMatch(error.stdout + error.stderr, .regex(".*compile_failure.*"))
                XCTAssertMatch(error.stdout + error.stderr, .regex(".*error:.*"))
            }
        }
    }

    func testPackageManagerDefineAndXArgs() async throws {
        try await fixtureXCTest(name: "Miscellaneous/-DSWIFT_PACKAGE") { fixturePath in
            await XCTAssertBuildFails(
                fixturePath,
                buildSystem: .native,
            )
            await XCTAssertBuilds(
                fixturePath,
                Xcc: ["-DEXTRA_C_DEFINE=2"],
                Xswiftc: ["-DEXTRA_SWIFTC_DEFINE"],
                buildSystem: .native,
            )
        }
    }

    /**
     Tests that modules that are rebuilt causes
     any executables that link to that module to be relinked.
    */
    func testInternalDependencyEdges() async throws {
        try await fixtureXCTest(name: "Miscellaneous/DependencyEdges/Internal") { fixturePath in
            let execpath = fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Foo").pathString

            await XCTAssertBuilds(
                fixturePath,
                buildSystem: .native,
            )
            var output = try await AsyncProcess.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "Hello\(ProcessInfo.EOL)")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            try localFileSystem.writeFileContents(fixturePath.appending(components: "Bar", "Bar.swift"), bytes: "public let bar = \"Goodbye\"\n")

            await XCTAssertBuilds(
                fixturePath,
                buildSystem: .native,
            )
            output = try await AsyncProcess.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "Goodbye\(ProcessInfo.EOL)")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables that link to that module in the root package.
    */
    func testExternalDependencyEdges1() async throws {
        try await fixtureXCTest(name: "DependencyResolution/External/Complex") { fixturePath in
            let execpath = fixturePath.appending(components: "app", ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Dealer").pathString

            let packageRoot = fixturePath.appending("app")
            await XCTAssertBuilds(
                packageRoot,
                buildSystem: .native,
            )
            var output = try await AsyncProcess.checkNonZeroExit(args: execpath).withSwiftLineEnding
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            let path = try SwiftPM.packagePath(for: "FisherYates", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "src", "Fisher-Yates_Shuffle.swift"), bytes: "public extension Collection{ func shuffle() -> [Iterator.Element] {return []} }\n\npublic extension MutableCollection where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerated() { self[i] = self[0] } }}\n\npublic let shuffle = true")

            await XCTAssertBuilds(
                fixturePath.appending("app"),
                buildSystem: .native,
            )
            output = try await AsyncProcess.checkNonZeroExit(args: execpath).withSwiftLineEnding
            XCTAssertEqual(output, "♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables for another external package to be rebuilt.
     */
    func testExternalDependencyEdges2() async throws {
        try await fixtureXCTest(name: "Miscellaneous/DependencyEdges/External") { fixturePath in
            let execpath = [fixturePath.appending(components: "root", ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "dep2").pathString]

            let packageRoot = fixturePath.appending("root")
            await XCTAssertBuilds(
                fixturePath.appending("root"),
                buildSystem: .native,
            )
            var output = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Hello\(ProcessInfo.EOL)")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            let path = try SwiftPM.packagePath(for: "dep1", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "Foo.swift"), bytes: "public let foo = \"Goodbye\"")

            await XCTAssertBuilds(
                fixturePath.appending("root"),
                buildSystem: .native,
            )
            output = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Goodbye\(ProcessInfo.EOL)")
        }
    }

    func testSpaces() async throws {
        try await fixtureXCTest(name: "Miscellaneous/Spaces Fixture") { fixturePath in
            await XCTAssertBuilds(
                fixturePath,
                buildSystem: .native,
            )
            XCTAssertFileExists(fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug", "Module_Name_1.build", "Foo.swift.o"))
        }
    }

    func testSecondBuildIsNullInModulemapGen() throws {
        // This has been failing on the Swift CI sometimes, need to investigate.
      #if false
        // Make sure that swiftpm doesn't rebuild second time if the modulemap is being generated.
        try fixtureXCTest(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            var output = try await executeSwiftBuild(
                prefix,
                buildSystem: .native,
            )
            XCTAssertFalse(output.isEmpty, output)
            output = try await executeSwiftBuild(
                prefix,
                buildSystem: .native,
            )
            XCTAssertTrue(output.isEmpty, output)
        }
      #endif
    }

    func testOverridingDeploymentTargetUsingSwiftCompilerArgument() async throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try await fixtureXCTest(name: "Miscellaneous/DistantFutureDeploymentTarget") { fixturePath in
            let hostTriple = try UserToolchain.default.targetTriple
            try await executeSwiftBuild(
                fixturePath,
                Xswiftc: ["-target", "\(hostTriple.archName)-apple-macosx41.0"],
                buildSystem: .native,
            )
        }
    }

    func testPkgConfigCFamilyTargets() async throws {
        try XCTSkipOnWindows(because: "fails to build on windows (maybe not be supported?)")
        try await fixtureXCTest(name: "Miscellaneous/PkgConfig") { fixturePath in
            let systemModule = fixturePath.appending("SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let triple = try UserToolchain.default.targetTriple
            let output =  systemModule.appending("libSystemModule\(triple.dynamicLibraryExtension)")
            try systemQuietly([executableName("clang"), "-shared", input.pathString, "-o", output.pathString])

            let pcFile = fixturePath.appending("libSystemModule.pc")

            try localFileSystem.writeFileContents(pcFile, string: """
                prefix=\(systemModule.pathString)
                exec_prefix=${prefix}
                libdir=${exec_prefix}
                includedir=${prefix}/Sources/include
                Name: SystemModule
                URL: http://127.0.0.1/
                Description: The one and only SystemModule
                Version: 1.10.0
                Cflags: -I${includedir}
                Libs: -L${libdir} -lSystemModule

                """
            )

            let moduleUser = fixturePath.appending("SystemModuleUserClang")
            let env: Environment = ["PKG_CONFIG_PATH": fixturePath.pathString]
            _ = try await executeSwiftBuild(
                moduleUser,
                env: env,
                buildSystem: .native,
            )

            XCTAssertFileExists(moduleUser.appending(components: ".build", triple.platformBuildPathComponent, "debug", "SystemModuleUserClang"))

            // Clean up the build directory before re-running the build with
            // different arguments.
            _ = try await executeSwiftPackage(
                moduleUser,
                extraArgs: ["clean"],
                buildSystem: .native,
            )

            _ = try await executeSwiftBuild(
                moduleUser,
                extraArgs: ["--pkg-config-path", fixturePath.pathString],
                buildSystem: .native,
            )

            XCTAssertFileExists(moduleUser.appending(components: ".build", triple.platformBuildPathComponent, "debug", "SystemModuleUserClang"))
        }
    }

    func testCanKillSubprocessOnSigInt() throws {
        // <rdar://problem/31890371> swift-pm: Spurious? failures of MiscellaneousTestCase.testCanKillSubprocessOnSigInt on linux
        #if false
        try fixtureXCTest(name: "DependencyResolution/External/Simple") { fixturePath in

            let fakeGit = fixturePath.appending(components: "bin", "git")
            let waitFile = fixturePath.appending(components: "waitfile")

            try localFileSystem.createDirectory(fakeGit.parentDirectory)

            // Write out fake git.
            try localFileSystem.writeFileContents(fakeGit, string:
                """
                    #!/bin/sh
                    set -e
                    printf "$$" >> \(waitFile)
                    while true; do sleep 1; done
                """
            )

            // Make it executable.
            _ = try AsyncProcess.popen(args: "chmod", "+x", fakeGit.description)

            // Put fake git in PATH.
            var env = ProcessInfo.processInfo.environment
            let oldPath = env["PATH"]
            env["PATH"] = fakeGit.parentDirectory.description
            if let oldPath {
                env["PATH"] = env["PATH"]! + ":" + oldPath
            }

            // Launch swift-build.
            let app = fixturePath.appending("Bar")
            let process = AsyncProcess(args: SwiftPM.Build.path.pathString, "--package-path", app.pathString, environment: env)
            try process.launch()

            guard waitForFile(waitFile) else {
                return XCTFail("Couldn't launch the process")
            }
            // Interrupt the process.
            process.signal(SIGINT)
            let result = try process.waitUntilExit()

            // We should not have exited with zero.
            XCTAssert(result.exitStatus != .terminated(code: 0))

            // Process and subprocesses should be dead.
            let contents: String = try localFileSystem.readFileContents(waitFile)
            XCTAssertFalse(try AsyncProcess.running(process.processID))
            XCTAssertFalse(try AsyncProcess.running(ProcessID(contents)!))
        }
        #endif
    }

    func testReportingErrorFromGitCommand() async throws {
        try await fixtureXCTest(name: "Miscellaneous/MissingDependency") { fixturePath in
            // This fixture has a setup that is intentionally missing a local
            // dependency to induce a failure.

            // Launch swift-build.
            let app = fixturePath.appending("Bar")

            await XCTAssertAsyncThrowsError(
                try await executeSwiftBuild(
                    app,
                    buildSystem: .native,
                )
            ) { error in
                // We should exited with a failure from the attempt to "git clone"
                // something that doesn't exist.
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssert(stderr.contains("error: Failed to clone repository"), "Error from git was not propagated to process output: \(stderr)")
            }
        }
    }

    func testLocalPackageUsedAsURLValidation() async throws {
        try await fixtureXCTest(name: "Miscellaneous/LocalPackageAsURL", createGitRepo: false) { fixturePath in
            // This fixture has a setup that is trying to use a local package
            // as a url that hasn't been initialized as a repo
            await XCTAssertAsyncThrowsError(
                try await executeSwiftBuild(
                    fixturePath.appending("Bar"),
                    buildSystem: .native,
                )
            ) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssert(stderr.contains("cannot clone from local directory"), "Didn't find expected output: \(stderr)")
            }
        }
    }

    func testLTO() async throws {
        throw XCTSkip("No longer works with newer toolchains")
        #if os(macOS)
        // FIXME: this test requires swift-driver to be installed
        // Currently swift-ci does not build/install swift-driver before running
        // swift-package-manager tests which results in this test failing.
        // See the following additional discussion:
        // - https://github.com/swiftlang/swift/pull/69696
        // - https://github.com/swiftlang/swift/pull/61766
        // - https://github.com/swiftlang/swift-package-manager/pull/5842#issuecomment-1301632685
        try await fixtureXCTest(name: "Miscellaneous/LTO/SwiftAndCTargets") { fixturePath in
            /*let output =*/
            try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--experimental-lto-mode=full", "--verbose"],
                buildSystem: .native,
            
            )
            // FIXME: On macOS dsymutil cannot find temporary .o files? (#6890)
            // Ensure warnings like the following are not present in build output
            // warning: (arm64) /var/folders/ym/6l_0x8vj0b70sz_4h9d70p440000gn/T/main-e120de.o unable to open object file: No such file or directory
            // XCTAssertNoMatch(output.stdout, .contains("unable to open object file"))
        }
        #endif
    }

    func testUnicode() async throws {
        try XCTSkipOnWindows(because: "Filepath too long error")
        #if !os(Linux) && !os(Android) // TODO: - Linux has trouble with this and needs investigation.
        try await fixtureXCTest(name: "Miscellaneous/Unicode") { fixturePath in
            // See the fixture manifest for an explanation of this string.
            let complicatedString = "πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄"
            let verify = "\u{03C0}\u{0FB2C}\u{00B5}\u{1D11E}\u{1F1FA}\u{1F1F3}\u{1F1EE}\u{1F1F1}\u{0078}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}"
            XCTAssert(
                complicatedString.unicodeScalars.elementsEqual(verify.unicodeScalars),
                "\(complicatedString) ≠ \(verify)")

            // ••••• Set up dependency.
            let dependencyName = "UnicodeDependency‐\(complicatedString)"
            let dependencyOrigin = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory
                .appending("Fixtures")
                .appending("Miscellaneous")
                .appending(component: dependencyName)
            let dependencyDestination = fixturePath.parentDirectory.appending(component: dependencyName)
            try? FileManager.default.removeItem(atPath: dependencyDestination.pathString)
            defer { try? FileManager.default.removeItem(atPath: dependencyDestination.pathString) }
            try FileManager.default.copyItem(
                atPath: dependencyOrigin.pathString,
                toPath: dependencyDestination.pathString)
            let dependency = GitRepository(path: dependencyDestination)
            try dependency.create()
            try dependency.stageEverything()
            try dependency.commit()
            try dependency.tag(name: "1.0.0")
            // •••••

            // Attempt several operations.
            try await executeSwiftTest(
                fixturePath,
                buildSystem: .native,
            )
            try await executeSwiftRun(
                fixturePath,
                complicatedString + "‐tool",
                buildSystem: .native,
            )
        }
        #endif
    }

    func testTestsCanLinkAgainstExecutable() async throws {
        try await fixtureXCTest(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    buildSystem: .native,
                )
                // in "swift test" build output goes to stderr
                XCTAssertMatch(stderr, .contains("Linking TestableExe1"))
                XCTAssertMatch(stderr, .contains("Linking TestableExe2"))
                XCTAssertMatch(stderr, .contains("Linking TestableExePackageTests"))
                XCTAssertMatch(stderr, .contains("Build complete!"))
                // in "swift test" test output goes to stdout
                XCTAssertMatch(stdout, .contains("Executed 1 test"))
                XCTAssertMatch(stdout, .contains("Hello, world"))
                XCTAssertMatch(stdout, .contains("Hello, planet"))
            } catch {
                #if os(macOS) && arch(arm64)
                // Add some logging but ignore the failure for an environment being investigated.
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    extraArgs: ["-v"],
                    buildSystem: .native,
                )
                print("testTestsCanLinkAgainstExecutable failed")
                print("ENV:\n")
                for (k, v) in Environment.current.sorted(by: { $0.key < $1.key }) {
                    print("  \(k)=\(v)")
                }
                print("STDOUT:\n\(stdout)")
                print("STDERR:\n\(stderr)")
                #else
                XCTFail("\(error)")
                #endif
            }
        }
    }

    @available(macOS 15, *)
    func testTestsCanLinkAgainstAsyncExecutable() async throws {
        try await fixtureXCTest(name: "Miscellaneous/TestableAsyncExe") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                buildSystem: .native,
            )
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Linking TestableAsyncExe1"))
            XCTAssertMatch(stderr, .contains("Linking TestableAsyncExe2"))
            XCTAssertMatch(stderr, .contains("Linking TestableAsyncExe3"))
            XCTAssertMatch(stderr, .contains("Linking TestableAsyncExe4"))
            XCTAssertMatch(stderr, .contains("Linking TestableAsyncExePackageTests"))
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("Executed 1 test"))
            XCTAssertMatch(stdout, .contains("Hello, async world"))
            XCTAssertMatch(stdout, .contains("Hello, async planet"))
            XCTAssertMatch(stdout, .contains("Hello, async galaxy"))
            XCTAssertMatch(stdout, .contains("Hello, async universe"))
        }
    }

    func testExecutableTargetMismatch() async throws {
        try await fixtureXCTest(name: "Miscellaneous/TargetMismatch") { path in
            do {
                let output = try await executeSwiftBuild(
                    path,
                    buildSystem: .native,
                )
                // in "swift build" build output goes to stdout
                XCTAssertMatch(output.stdout, .contains("Compiling Sample main.swift"))
                XCTAssertMatch(output.stderr, .contains("The target named 'Sample' was identified as an executable target but a non-executable product with this name already exists."))
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testLibraryTriesToIncludeExecutableTarget() async throws {
        try await fixtureXCTest(name: "Miscellaneous/PackageWithMalformedLibraryProduct") { path in
            await XCTAssertThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    path,
                    buildSystem: .native,
                )
            ) { error in
                // if our code crashes we'll get an exit code of 256
                guard error.result.exitStatus == .terminated(code: 1) else {
                    return XCTFail("failed in an unexpected manner: \(error)")
                }
                XCTAssertMatch(error.stdout + error.stderr, .contains("library product 'PackageWithMalformedLibraryProduct' should not contain executable targets (it has 'PackageWithMalformedLibraryProduct')"))
            }
        }
    }

    func testEditModeEndToEnd() async throws {
        try await fixtureXCTest(name: "Miscellaneous/Edit") { fixturePath in
            #if os(Windows)
            let prefix = fixturePath
            #else
            let prefix = try resolveSymlinks(fixturePath)
            #endif
            let appPath = fixturePath.appending("App")

            // prepare the dependencies as git repos
            for directory in ["Foo", "Bar"] {
                let path = fixturePath.appending(component: directory)
                _ = try await AsyncProcess.checkNonZeroExit(args: Git.tool, "-C", path.pathString, "init")
            }

            do {
                // make sure it builds
                let output = try await executeSwiftBuild(
                    appPath,
                    buildSystem: .native,
                )
                // package resolution output goes to stderr
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("Foo").pathString)"))
                XCTAssertMatch(output.stderr, .contains("Fetched \(prefix.appending("Foo").pathString)"))
                XCTAssertMatch(output.stderr, .contains("Creating working copy for \(prefix.appending("Foo").pathString)"))
                XCTAssertMatch(output.stderr, .contains("Fetching \(prefix.appending("Bar").pathString)"))
                XCTAssertMatch(output.stderr, .contains("Fetched \(prefix.appending("Bar").pathString)"))
                XCTAssertMatch(output.stderr, .contains("Creating working copy for \(prefix.appending("Bar").pathString)"))
                // in "swift build" build output goes to stdout
                XCTAssertMatch(output.stdout, .contains("Build complete!"))
            }

            // put foo into edit mode
            _ = try await executeSwiftPackage(
                appPath,
                extraArgs: ["edit", "Foo"],
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(appPath.appending(components: ["Packages", "Foo"]))

            do {
                // build again in edit mode
                let output = try await executeSwiftBuild(
                    appPath,
                    buildSystem: .native,
                )
                XCTAssertMatch(output.stdout, .contains("Build complete!"))
            }

            do {
                // take foo out of edit mode
                let output = try await executeSwiftPackage(
                    appPath,
                    extraArgs: ["unedit", "Foo"],
                    buildSystem: .native,
                )
                // package resolution output goes to stderr
                XCTAssertMatch(output.stderr, .contains("Creating working copy for \(prefix.appending("Foo"))"))
                XCTAssertNoSuchPath(appPath.appending(components: ["Packages", "Foo"]))
            }

            // build again in edit mode
            do {
                let output = try await executeSwiftBuild(
                    appPath,
                    buildSystem: .native,
                )
                // in "swift build" build output goes to stdout
                XCTAssertMatch(output.stdout, .contains("Build complete!"))
            }
        }
    }

    func testCustomCachePath() async throws {
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            let customCachePath = path.appending(components: "custom", "cache")
            XCTAssertNoSuchPath(customCachePath)
            try await executeSwiftBuild(
                path,
                extraArgs: ["--cache-path", customCachePath.pathString],
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(customCachePath)
        }

        // `FileSystem` does not support `chmod` on Linux
        #if os(macOS)
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            try localFileSystem.chmod(.userUnWritable, path: path)
            let customCachePath = path.appending(components: "custom", "cache")
            XCTAssertNoSuchPath(customCachePath)
            await XCTAssertAsyncThrowsError(
                try await executeSwiftBuild(
                    path,
                    extraArgs: ["--cache-path", customCachePath.pathString],
                    buildSystem: .native,
                )
            ) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssert(stderr.contains("error: You don’t have permission"), "expected permissions error. stderr: '\(stderr)'")
            }
            XCTAssertNoSuchPath(customCachePath)
        }
        #endif
    }

    func testCustomConfigPath() async throws {
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            let customConfigPath = path.appending(components: "custom", "config")
            XCTAssertNoSuchPath(customConfigPath)
            try await executeSwiftBuild(
                path,
                extraArgs: ["--config-path", customConfigPath.pathString],
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(customConfigPath)
        }

        // `FileSystem` does not support `chmod` on Linux
        #if os(macOS)
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            try localFileSystem.chmod(.userUnWritable, path: path)
            let customConfigPath = path.appending(components: "custom", "config")
            XCTAssertNoSuchPath(customConfigPath)
            await XCTAssertAsyncThrowsError(
                try await executeSwiftBuild(
                    path,
                    extraArgs: ["--config-path", customConfigPath.pathString],
                    buildSystem: .native,
                )
            ) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssert(stderr.contains("error: You don’t have permission"), "expected permissions error. stderr: '\(stderr)'")
            }
            XCTAssertNoSuchPath(customConfigPath)
        }
        #endif
    }

    func testCustomSecurityPath() async throws {
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            let customSecurityPath = path.appending(components: "custom", "security")
            XCTAssertNoSuchPath(customSecurityPath)
            try await executeSwiftBuild(
                path,
                extraArgs: ["--security-path", customSecurityPath.pathString],
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(customSecurityPath)
        }

        // `FileSystem` does not support `chmod` on Linux
        #if os(macOS)
        try await fixtureXCTest(name: "Miscellaneous/Simple") { path in
            try localFileSystem.chmod(.userUnWritable, path: path)
            let customSecurityPath = path.appending(components: "custom", "security")
            XCTAssertNoSuchPath(customSecurityPath)
            await XCTAssertAsyncThrowsError(
                try await executeSwiftBuild(
                    path,
                    extraArgs: ["--security-path", customSecurityPath.pathString],
                    buildSystem: .native,
                )
            ) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssert(stderr.contains("error: You don’t have permission"), "expected permissions error. stderr: '\(stderr)'")
            }
        }
        #endif
    }

    func testPluginGeneratedResources() async throws {
        // Only run the test if the environment in which we're running actually supports Swift concurrency (which the plugin APIs require).
        try XCTSkipIf(!UserToolchain.default.supportsSwiftConcurrency(), "skipping because test environment doesn't support concurrency")
        try XCTSkipOnWindows(
            because: """
            Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )

        try await fixtureXCTest(name: "Miscellaneous/PluginGeneratedResources") { path in
            let result = try await executeSwiftRun(
                path,
                nil,
                buildSystem: .native,
            )
            XCTAssertEqual(result.stdout, "Hello, World!\n", "executable did not produce expected output")
            XCTAssertTrue(result.stderr.contains("Copying best.txt\n"), "build log is missing message about copying resource file")
        }
    }

    func testCompileCXX17CrashWithFModules() async throws {
        try await fixtureXCTest(name: "Miscellaneous/CXX17CompilerCrash/v5_8") { fixturePath in
            await XCTAssertBuilds(
                fixturePath,
                buildSystem: .native,
            )
        }
    }

    func testNoJSONOutputWithFlatPackageStructure() async throws {
        try await fixtureXCTest(name: "Miscellaneous/FlatPackage") { package in
            // First build, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout1, stderr1) = try await executeSwiftBuild(
                package,
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(package.appending(".build"))
            XCTAssertNoMatch(stdout1, .contains("command_arguments"))
            XCTAssertNoMatch(stderr1, .contains("command_arguments"))
            
            // Now test, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout2, stderr2) = try await executeSwiftTest(
                package,
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(package.appending(".build"))
            XCTAssertNoMatch(stdout2, .contains("command_arguments"))
            XCTAssertNoMatch(stderr2, .contains("command_arguments"))
        }
    }

    func testNoWarningFromRemoteDependencies() async throws {
        try await fixtureXCTest(name: "Miscellaneous/DependenciesWarnings") { path in
            // prepare the deps as git sources
            let dependency1Path = path.appending("dep1")
            initGitRepo(dependency1Path, tag: "1.0.0")
            let dependency2Path = path.appending("dep2")
            initGitRepo(dependency2Path, tag: "1.0.0")

            let appPath = path.appending("app")
            let (stdout, stderr) = try await executeSwiftBuild(
                appPath,
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(appPath.appending(".build"))
            XCTAssertMatch(stdout + stderr, .contains("'DeprecatedApp' is deprecated"))
            XCTAssertNoMatch(stdout + stderr, .contains("'Deprecated1' is deprecated"))
            XCTAssertNoMatch(stdout + stderr, .contains("'Deprecated2' is deprecated"))
        }
    }

    func testNoWarningFromRemoteDependenciesWithWarningsAsErrors() async throws {
        try await fixtureXCTest(name: "Miscellaneous/DependenciesWarnings2") { path in
            // prepare the deps as git sources
            let dependency1Path = path.appending("dep1")
            initGitRepo(dependency1Path, tag: "1.0.0")
            let dependency2Path = path.appending("dep2")
            initGitRepo(dependency2Path, tag: "1.0.0")

            let appPath = path.appending("app")
            let (stdout, stderr) = try await executeSwiftBuild(
                appPath,
                Xswiftc: ["-warnings-as-errors"],
                buildSystem: .native,
            )
            XCTAssertDirectoryExists(appPath.appending(".build"))
            XCTAssertNoMatch(stdout + stderr, .contains("'Deprecated1' is deprecated"))
            XCTAssertNoMatch(stdout + stderr, .contains("'Deprecated2' is deprecated"))
        }
    }

    func testRootPackageWithConditionals() async throws {
        try await fixtureXCTest(name: "Miscellaneous/RootPackageWithConditionals") { path in
            let (_, stderr) = try await executeSwiftBuild(
                path,
                env: ["SWIFT_DRIVER_SWIFTSCAN_LIB" : "/this/is/a/bad/path"],
                buildSystem: .native,
            )
            let errors = stderr.components(separatedBy: .newlines).filter { !$0.contains("[logging] misuse") && !$0.isEmpty }
                                                                  .filter { !$0.contains("Unable to locate libSwiftScan") }
            XCTAssertEqual(errors, [], "unexpected errors: \(errors)")
        }
    }

    func testRootPackageWithConditionalsSwiftBuild() async throws {
        try XCTSkipOnWindows(because: "produces a filename that is too long, needs investigation")
#if os(Linux)
        if FileManager.default.contents(atPath: "/etc/system-release").map { String(decoding: $0, as: UTF8.self) == "Amazon Linux release 2 (Karoo)\n" } ?? false {
            throw XCTSkip("Skipping Swift Build testing on Amazon Linux because of platform issues.")
        }
#endif
        try await fixtureXCTest(name: "Miscellaneous/RootPackageWithConditionals") { path in
            _ = try await executeSwiftBuild(
                path,
                extraArgs: ["--build-system=swiftbuild"],
                env: ["SWIFT_DRIVER_SWIFTSCAN_LIB" : "/this/is/a/bad/path"],
                buildSystem: .native,
            )
        }
    }
}
