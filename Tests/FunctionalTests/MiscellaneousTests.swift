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
import SourceControl
import _InternalTestSupport
import Workspace
import Testing

import class Basics.AsyncProcess
import enum TSCUtility.Git

typealias ProcessID = AsyncProcess.ProcessID

@Suite(
    .tags(
        .TestSize.large,
    )
)
struct MiscellaneousTestCase {
    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func printsSelectedDependencyVersion(
        data: BuildData,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let (stdout, stderr) = try await executeSwiftBuild(
                fixturePath.appending("Bar"),
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            // package resolution output goes to stderr
            let packageRegex = try Regex("Computed .* at 1\\.2\\.3")
            #expect(stderr.contains(packageRegex))
            // in "swift build" build output goes to stdout
            if data.buildSystem == .native {
                #expect(stdout.contains("Compiling Foo Foo.swift"))
                #expect(stdout.contains("Compiling Bar main.swift"))
                if (data.config == .debug) {
                    #expect(stdout.contains("Merging module Foo") || stdout.contains("Emitting module Foo"))
                    #expect(stdout.contains("Merging module Bar") || stdout.contains("Emitting module Bar"))
                }
                #expect(stdout.contains("Linking Bar"))
            }
            #expect(stdout.contains("Build complete!"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func passExactDependenciesToBuildCommand(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/ExactDependencies") { fixturePath in
            let packagePath = fixturePath.appending("app")
            try await executeSwiftBuild(
                packagePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            let buildDir = try packagePath.appending(components: data.buildSystem.binPath(for: data.config))
            expectFileExists(at: buildDir.appending(executableName("FooExec")))
            if data.buildSystem == .native {
                expectFileExists(at: buildDir.appending(components: "Modules", "FooLib1.swiftmodule"))
                expectFileExists(at: buildDir.appending(components: "Modules", "FooLib2.swiftmodule"))
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func canBuildMoreThanTwiceWithExternalDependencies(
        data: BuildData
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func noArgumentsExitsWithOne(
        data: BuildData,
    ) async throws {
        await expectThrowsCommandExecutionError(
            try await executeSwiftBuild(
                "/",
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
        ) { error in
            // if our code crashes we'll get an exit code of 256
            guard error.result.exitStatus == .terminated(code: 1) else {
                Issue.record("failed in an unexpected manner: \(error)")
                return
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func compileFailureExitsGracefully(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/CompileFails") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                // if our code crashes we'll get an exit code of 256
                guard error.result.exitStatus == .terminated(code: 1) else {
                    Issue.record("failed in an unexpected manner: \(error)")
                    return
                }
                if data.buildSystem == .native {
                    #expect((error.stdout + error.stderr).contains("Compiling CompileFails Foo.swift"))
                    #expect((error.stdout + error.stderr).contains("compile_failure"))
                }
                #expect((error.stdout + error.stderr).contains("error:"))
            }
        }
    }

    @Test(
        // TODO: raise a GitHub issue on 
        //  swift run swift-build --package-path Fixtures/Miscellaneous/-DSWIFT_PACKAGE --configuration release -Xcc -DEXTRA_C_DEFINE=2 -Xswiftc -DEXTRA_SWIFTC_DEFINE --build-system swiftbuild
        //  swift run swift-build --package-path Fixtures/Miscellaneous/-DSWIFT_PACKAGE --configuration debug -Xcc -DEXTRA_C_DEFINE=2 -Xswiftc -DEXTRA_SWIFTC_DEFINE --build-system swiftbuild
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func packageManagerDefineAndXArgs(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/-DSWIFT_PACKAGE") { fixturePath in
            await #expect(throws: SwiftPMError.self) {
                try await executeSwiftBuild(
                    fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                )
            }
            try await withKnownIssue {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    Xcc: ["-DEXTRA_C_DEFINE=2"],
                    Xswiftc: ["-DEXTRA_SWIFTC_DEFINE"],
                    buildSystem: data.buildSystem,
                )
            } when: {
                data.buildSystem == .swiftbuild
            }
        }
    }

    /**
     Tests that modules that are rebuilt causes
     any executables that link to that module to be relinked.
     */
    @Test(
        .IssueSwiftBuildLinuxRunnable,
        .tags(
            .Feature.Command.Build,
        ),
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func internalDependencyEdges(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/DependencyEdges/Internal") { fixturePath in
            let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
            let executable = binPath.appending(components: "Foo")
            let execPath = executable.pathString

            try await executeSwiftBuild(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try #require(localFileSystem.exists(executable), "File \(executable) does not exist")
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(args: execPath)
                #expect(output == "Hello\(ProcessInfo.EOL)")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            try localFileSystem.writeFileContents(fixturePath.appending(components: "Bar", "Bar.swift"), bytes: "public let bar = \"Goodbye\"\n")

            try await executeSwiftBuild(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try #require(localFileSystem.exists(executable), "File \(executable) does not exist")
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(args: execPath)
                #expect(output == "Goodbye\(ProcessInfo.EOL)")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables that link to that module in the root package.
     */
    @Test(
        .IssueSwiftBuildLinuxRunnable,
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func externalDependencyEdges1(
        data: BuildData
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
            let packageRoot = fixturePath.appending(component: "app")
            let binPath = try packageRoot.appending(components: data.buildSystem.binPath(for: data.config))
            let executable = binPath.appending(component: "Dealer")
            let execPath = executable.pathString

            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try #require(localFileSystem.exists(executable), "File \(executable) does not exist.")
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(args: execPath).withSwiftLineEnding
                #expect(output == "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            let path = try SwiftPM.packagePath(for: "FisherYates", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "src", "Fisher-Yates_Shuffle.swift"), bytes: "public extension Collection{ func shuffle() -> [Iterator.Element] {return []} }\n\npublic extension MutableCollection where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerated() { self[i] = self[0] } }}\n\npublic let shuffle = true")

            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try #require(localFileSystem.exists(executable), "File \(executable) does not exist.")
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(args: execPath).withSwiftLineEnding
                #expect(output == "♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables for another external package to be rebuilt.
     */
    @Test(
        .IssueSwiftBuildLinuxRunnable,
        .tags(
            .Feature.Command.Build,
        ),
        // arguments: getBuildData(for: [.swiftbuild]),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func externalDependencyEdges2(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/DependencyEdges/External") { fixturePath in
            let packageRoot = fixturePath.appending("root")
            let binPath = try packageRoot.appending(components: data.buildSystem.binPath(for: data.config))
            let executable = binPath.appending(component: "dep2")
            let execpath = [executable.pathString]

            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try requireFileExists(at: executable)
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
                #expect(output == "Hello\(ProcessInfo.EOL)")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            let path = try SwiftPM.packagePath(for: "dep1", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "Foo.swift"), bytes: "public let foo = \"Goodbye\"")

            try await executeSwiftBuild(
                packageRoot,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            try #require(localFileSystem.exists(executable), "File \"\(execpath)\" does not exists")
            try await withKnownIssue {
                let output = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
                #expect(output == "Goodbye\(ProcessInfo.EOL)")
            } when: {
                data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }
        }
    }

    @Test(
        .IssueSwiftBuildSpaceInPath,
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func spaces(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/Spaces Fixture") { fixturePath in
                await #expect(throws: Never.self) {
                    try await executeSwiftBuild(
                        fixturePath,
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                }
                let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                if data.buildSystem == .native {
                    expectFileExists(at: binPath.appending(components: "Module_Name_1.build", "Foo.swift.o"))
                }
            }
        } when: {
            data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
        }
    }

    @Test(
        .disabled("XCTest was disabled"),
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func secondBuildIsNullInModulemapGen(
        data: BuildData,
    ) async throws {
        // Make sure that swiftpm doesn't rebuild second time if the modulemap is being generated.
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            let output = try await executeSwiftBuild(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            ).stdout
            #expect(!output.isEmpty)
            let secondOutput = try await executeSwiftBuild(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            ).stdout
            #expect(secondOutput.isEmpty)
        }
    }

    @Test(
        // TODO: Raise a GitHub issue as Swift Build fails
        //.   swift run swift-build --package-path Fixtures/Miscellaneous/DistantFutureDeploymentTarget --configuration release -Xswiftc -target -Xswiftc arm64-apple-macosx41.0 --build-system swiftbuild
        //.   swift run swift-build --package-path Fixtures/Miscellaneous/DistantFutureDeploymentTarget --configuration debug -Xswiftc -target -Xswiftc arm64-apple-macosx41.0 --build-system swiftbuild
        .requireHostOS(.macOS),
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func overridingDeploymentTargetUsingSwiftCompilerArgument(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/DistantFutureDeploymentTarget") { fixturePath in
                let hostTriple = try UserToolchain.default.targetTriple
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    Xswiftc: ["-target", "\(hostTriple.archName)-apple-macosx41.0"],
                    buildSystem: data.buildSystem,
                )
            }
        } when: {
            data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .serialized, // Because the tests set the environment variable
        // TODO: raise a GitHub issue .  the second `swift-build` command fails.
        .tags(
            .Feature.Command.Build,
        ),
        .requires(executable: executableName("clang")),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func pkgConfigCFamilyTargets(
        data: BuildData,
    ) async throws {
        // try XCTSkipOnWindows(because: "fails to build on windows (maybe not be supported?)")
        try await fixture(name: "Miscellaneous/PkgConfig") { fixturePath in
            let systemModule = fixturePath.appending("SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let triple = try UserToolchain.default.targetTriple
            let output = systemModule.appending("libSystemModule\(triple.dynamicLibraryExtension)")
            try await AsyncProcess.checkNonZeroExit(args: executableName("clang"), "-shared", input.pathString, "-o", output.pathString)

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
            let binPath = try moduleUser.appending(components: data.buildSystem.binPath(for: data.config))
            await withKnownIssue {
                await #expect(throws: Never.self) {
                    _ = try await executeSwiftBuild(
                        moduleUser,
                        configuration: data.config,
                        env: env,
                        buildSystem: data.buildSystem,
                    )
                }
                expectFileExists(at: binPath.appending(component: "SystemModuleUserClang"))
            } when:{
                data.buildSystem == .swiftbuild && data.config == .release && ProcessInfo.hostOperatingSystem != .linux
            }

            // Clean up the build directory before re-running the build with
            // different arguments.
            _ = try await executeSwiftPackage(
                moduleUser,
                configuration: data.config,
                extraArgs: ["clean"],
                buildSystem: data.buildSystem,
            )

            await withKnownIssue {
                await #expect(throws: Never.self) {
                    _ = try await executeSwiftBuild(
                        moduleUser,
                        configuration: data.config,
                        extraArgs: ["--pkg-config-path", fixturePath.pathString],
                        buildSystem: data.buildSystem,
                    )
                }

                expectFileExists(at: binPath.appending(component: "SystemModuleUserClang"))
            } when: {
                data.buildSystem == .swiftbuild
            }
        }
    }

    @Test(
        .disabled("XCTest was disabled"),
        .tags(
            .Feature.Command.Build,
        ),
    )
    func canKillSubprocessOnSigInt() throws {
#if false
        try fixture(name: "DependencyResolution/External/Simple") { fixturePath in

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
                Issue.record("Couldn't launch the process")
                return
            }
            // Interrupt the process.
            process.signal(SIGINT)
            let result = try process.waitUntilExit()

            // We should not have exited with zero.
            #expect(result.exitStatus != .terminated(code: 0))

            // Process and subprocesses should be dead.
            let contents: String = try localFileSystem.readFileContents(waitFile)
            try #expect(!AsyncProcess.running(process.processID))
            try #expect(!AsyncProcess.running(ProcessID(contents)!))
        }
#endif
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func reportingErrorFromGitCommand(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/MissingDependency") { fixturePath in
            // This fixture has a setup that is intentionally missing a local
            // dependency to induce a failure.

            // Launch swift-build.
            let app = fixturePath.appending("Bar")

            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    app,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                // We should exited with a failure from the attempt to "git clone"
                // something that doesn't exist.
                let stderr = error.stderr
                #expect(
                    stderr.contains("error: Failed to clone repository"),
                    "Error from git was not propagated to process output: \(stderr)",
                )
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func localPackageUsedAsURLValidation(
        data: BuildData
    ) async throws {
        try await fixture(name: "Miscellaneous/LocalPackageAsURL", createGitRepo: false) { fixturePath in
            // This fixture has a setup that is trying to use a local package
            // as a url that hasn't been initialized as a repo
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath.appending("Bar"),
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                let stderr = error.stderr
                #expect(
                    stderr.contains("cannot clone from local directory"),
                    "Didn't find expected output: \(stderr)",
                )
            }
        }
    }

    @Test(
        .disabled("No longer works with newer toolchains"),
    )
    func lTO() async throws {
#if os(macOS)
        // FIXME: this test requires swift-driver to be installed
        // Currently swift-ci does not build/install swift-driver before running
        // swift-package-manager tests which results in this test failing.
        // See the following additional discussion:
        // - https://github.com/swiftlang/swift/pull/69696
        // - https://github.com/swiftlang/swift/pull/61766
        // - https://github.com/swiftlang/swift-package-manager/pull/5842#issuecomment-1301632685
        try await fixture(name: "Miscellaneous/LTO/SwiftAndCTargets") { fixturePath in
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

    @Test(
        .IssueWindowsLongPath,
        .IssueSwiftBuildLinuxRunnable,
        .skipHostOS(.linux),
        .skipHostOS(.android),
        .tags(
            .Feature.Command.Test,
            .Feature.Command.Run,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func unicode(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/Unicode") { fixturePath in
                // See the fixture manifest for an explanation of this string.
                let complicatedString = "πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄"
                let verify = "\u{03C0}\u{0FB2C}\u{00B5}\u{1D11E}\u{1F1FA}\u{1F1F3}\u{1F1EE}\u{1F1F1}\u{0078}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}"
                #expect(
                    complicatedString.unicodeScalars.elementsEqual(verify.unicodeScalars),
                    "\(complicatedString) ≠ \(verify)",
                )

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
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                try await withKnownIssue {
                    try await executeSwiftRun(
                        fixturePath,
                        complicatedString + "‐tool",
                        configuration: data.config,
                        buildSystem: data.buildSystem,
                    )
                } when: {
                    ProcessInfo.hostOperatingSystem == .linux && data.buildSystem == .swiftbuild
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .skipHostOS(.linux), // TODO: raise GitHub issue.. crashed on Linux
        .tags(
            .Feature.Command.Test,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func testsCanLinkAgainstExecutable(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                // in "swift test" build output goes to stderr
                if data.buildSystem == .native {
                    #expect(stderr.contains("Linking TestableExe1"))
                    #expect(stderr.contains("Linking TestableExe2"))
                    #expect(stderr.contains("Linking TestableExePackageTests"))
                }
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("Executed 1 test"))
                #expect(stdout.contains("Hello, world"))
                #expect(stdout.contains("Hello, planet"))
            } catch {
#if os(macOS) && arch(arm64)
                // Add some logging but ignore the failure for an environment being investigated.
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: data.config,
                    extraArgs: ["-v"],
                    buildSystem: data.buildSystem,
                )
                print("\(String(describing: Test.current?.name)) failed")
                print("ENV:\n")
                for (k, v) in Environment.current.sorted(by: { $0.key < $1.key }) {
                    print("  \(k)=\(v)")
                }
                print("STDOUT:\n\(stdout)")
                print("STDERR:\n\(stderr)")
#else
                Issue.record("\(error)")
#endif
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    @available(macOS 15, *)
    func testsCanLinkAgainstAsyncExecutable(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/TestableAsyncExe") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            // in "swift test" build output goes to stderr
            if data.buildSystem == .native {
                #expect(stderr.contains("Linking TestableAsyncExe1"))
                #expect(stderr.contains("Linking TestableAsyncExe2"))
                #expect(stderr.contains("Linking TestableAsyncExe3"))
                #expect(stderr.contains("Linking TestableAsyncExe4"))
                #expect(stderr.contains("Linking TestableAsyncExePackageTests"))
            }
            #expect(stderr.contains("Build complete!"))
            // in "swift test" test output goes to stdout
            #expect(stdout.contains("Executed 1 test"))
            #expect(stdout.contains("Hello, async world"))
            #expect(stdout.contains("Hello, async planet"))
            #expect(stdout.contains("Hello, async galaxy"))
            #expect(stdout.contains("Hello, async universe"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func executableTargetMismatch(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/TargetMismatch") { path in
            let (stdout, stderr) = try await executeSwiftBuild(
                path,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            // in "swift build" build output goes to stdout
            if data.buildSystem == .native {
                #expect(stdout.contains("Compiling Sample main.swift"))
            }
            #expect(stderr.contains("The target named 'Sample' was identified as an executable target but a non-executable product with this name already exists."))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func libraryTriesToIncludeExecutableTarget(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/PackageWithMalformedLibraryProduct") { path in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    path,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            ) { error in
                // if our code crashes we'll get an exit code of 256
                guard error.result.exitStatus == .terminated(code: 1) else {
                    Issue.record("failed in an unexpected manner: \(error)")
                    return
                }
                #expect((error.stdout + error.stderr).contains("library product 'PackageWithMalformedLibraryProduct' should not contain executable targets (it has 'PackageWithMalformedLibraryProduct')"))
            }
        }
    }

     @Test(
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Package.Edit,
            .Feature.Command.Package.Unedit,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func editModeEndToEnd(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/Edit") { fixturePath in
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
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                // package resolution output goes to stderr
                #expect(output.stderr.contains("Fetching \(prefix.appending("Foo").pathString)"))
                #expect(output.stderr.contains("Fetched \(prefix.appending("Foo").pathString)"))
                #expect(output.stderr.contains("Creating working copy for \(prefix.appending("Foo").pathString)"))
                #expect(output.stderr.contains("Fetching \(prefix.appending("Bar").pathString)"))
                #expect(output.stderr.contains("Fetched \(prefix.appending("Bar").pathString)"))
                #expect(output.stderr.contains("Creating working copy for \(prefix.appending("Bar").pathString)"))
                // in "swift build" build output goes to stdout
                #expect(output.stdout.contains("Build complete!"))
            }

            // put foo into edit mode
            _ = try await executeSwiftPackage(
                appPath,
                configuration: data.config,
                extraArgs: ["edit", "Foo"],
                buildSystem: data.buildSystem,
            )
            expectDirectoryExists(at: appPath.appending(components: ["Packages", "Foo"]))

            do {
                // build again in edit mode
                let output = try await executeSwiftBuild(
                    appPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(output.stdout.contains("Build complete!"))
            }

            do {
                // take foo out of edit mode
                let output = try await executeSwiftPackage(
                    appPath,
                    configuration: data.config,
                    extraArgs: ["unedit", "Foo"],
                    buildSystem: data.buildSystem,
                )
                // package resolution output goes to stderr
                #expect(output.stderr.contains("Creating working copy for \(prefix.appending("Foo"))"))
                expectFileDoesNotExists(at: appPath.appending(components: ["Packages", "Foo"]))
            }

            // build again in edit mode
            do {
                let output = try await executeSwiftBuild(
                    appPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                // in "swift build" build output goes to stdout
                #expect(output.stdout.contains("Build complete!"))
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),[ "cache-path", "config-path", "security-path"],
    )
    func customCachePath(
        data: BuildData,
        pathOption: String,
    ) async throws {
        try await fixture(name: "Miscellaneous/Simple") { path in
            let customPath = path.appending(components: "custom", pathOption)
            expectFileDoesNotExists(at: customPath)
            expectDirectoryDoesNotExist(at: customPath)
            try await executeSwiftBuild(
                path,
                configuration: data.config,
                extraArgs: ["--\(pathOption)", customPath.pathString],
                buildSystem: data.buildSystem,
            )
            expectDirectoryExists(at: customPath)
        }
    }

    @Test(
        // .requireHostOS(.macOS), /// we should test this on Linux
        .skipHostOS(.linux), /// Skipping on Linux, but does chmod work on Windows?
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),[ "cache-path", "config-path", "security-path"],
    )
    func customPathUserUnwritableGeneratesPermissionError(
        data: BuildData,
        pathOption: String,
    ) async throws {
        try await fixture(name: "Miscellaneous/Simple") { path in
            // `FileSystem` does not support `chmod` on Linux
            try localFileSystem.chmod(.userUnWritable, path: path)
            defer {
                do {
                    try localFileSystem.chmod(.userWritable, path: path)
                } catch {
                    // Do nothing
                }
            }
            let customPath = path.appending(components: "custom", pathOption)
            expectFileDoesNotExists(at: customPath)
            expectDirectoryDoesNotExist(at: customPath)
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    path,
                    configuration: data.config,
                    extraArgs: ["--\(pathOption)", customPath.pathString],
                    buildSystem: data.buildSystem,
                )
            ) { error in
                let stderr = error.stderr
                #expect(stderr.contains("error: invalid access to"), "expected permissions error. stderr: '\(stderr)', stdout '\(error.stdout)'")
            }
            expectFileDoesNotExists(at: customPath)
            expectDirectoryDoesNotExist(at: customPath)
        }
    }


    @Test(
        .IssueSwiftBuildLinuxRunnable,
        .IssueWindowsRelativePathAssert,
        .IssueWindowsAbsoluteAndRelativePathTestFailures,
        // TODO: raise github issue..  swift run fails to execute the executable
        //     Build complete! (4.65 secs.)
        //     PluginGeneratedResources/PluginGeneratedResources.swift:9: Fatal error: Unexpectedly found nil while unwrapping an Optional value
        //     [1]    13225 trace trap  swift run swift-run --package-path  --configuration debug --build-system 
        .requiresSwiftConcurrencySupport,
        .tags(
            .Feature.Command.Run,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func pluginGeneratedResources(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/PluginGeneratedResources") { path in
                let result = try await executeSwiftRun(
                    path,
                    nil,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                #expect(result.stdout == "Hello, World!\n")
                #expect(result.stderr.contains("Copying best.txt\n"), "build log is missing message about copying resource file")
            }
        }when: {
            (data.buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux)
            || (data.buildSystem == .swiftbuild)
            || (ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline)
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func compileCXX17CrashWithFModules(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/CXX17CompilerCrash/v5_8") { fixturePath in
            await #expect(throws: Never.self) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func noJSONOutputWithFlatPackageStructure(
        data: BuildData,
    ) async throws {
        try await fixture(name: "Miscellaneous/FlatPackage") { package in
            // First build, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout1, stderr1) = try await executeSwiftBuild(
                package,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            expectDirectoryExists(at: package.appending(".build"))
            #expect(!stdout1.contains("command_arguments"))
            #expect(!stderr1.contains("command_arguments"))

            // Now test, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout2, stderr2) = try await executeSwiftTest(
                package,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            expectDirectoryExists(at: package.appending(".build"))
            #expect(!stdout2.contains("command_arguments"))
            #expect(!stderr2.contains("command_arguments"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9078", relationship: .defect),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func noWarningFromRemoteDependencies(
        data: BuildData,
    ) async throws {
        try withKnownIssue {
            try await fixture(name: "Miscellaneous/DependenciesWarnings") { path in
                // prepare the deps as git sources
                let dependency1Path = path.appending("dep1")
                initGitRepo(dependency1Path, tag: "1.0.0")
                let dependency2Path = path.appending("dep2")
                initGitRepo(dependency2Path, tag: "1.0.0")

                let appPath = path.appending("app")
                let (stdout, stderr) = try await executeSwiftBuild(
                    appPath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                expectDirectoryExists(at: appPath.appending(".build"))
                #expect((stdout + stderr).contains("'DeprecatedApp' is deprecated"))
                #expect(!(stdout + stderr).contains("'Deprecated1' is deprecated"))
                #expect(!(stdout + stderr).contains("'Deprecated2' is deprecated"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .linux    && data.buildSystem == .swiftbuild
        }
    }

    @Test(
        //TODO: Raise issue against SwiftBuild
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func noWarningFromRemoteDependenciesWithWarningsAsErrors(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/DependenciesWarnings2") { path in
                // prepare the deps as git sources
                let dependency1Path = path.appending("dep1")
                initGitRepo(dependency1Path, tag: "1.0.0")
                let dependency2Path = path.appending("dep2")
                initGitRepo(dependency2Path, tag: "1.0.0")

                let appPath = path.appending("app")
                let (stdout, stderr) = try await executeSwiftBuild(
                    appPath,
                    configuration: data.config,
                    Xswiftc: ["-warnings-as-errors"],
                    buildSystem: data.buildSystem,
                )
                expectDirectoryExists(at: appPath.appending(".build"))
                #expect(!(stdout + stderr).contains("'Deprecated1' is deprecated"))
                #expect(!(stdout + stderr).contains("'Deprecated2' is deprecated"))
            }
        } when: {
            data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .tags(
            .Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms)
    )
    func rootPackageWithConditionals(
        data: BuildData,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Miscellaneous/RootPackageWithConditionals") { path in
                let (_, stderr) = try await executeSwiftBuild(
                    path,
                    configuration: data.config,
                    env: ["SWIFT_DRIVER_SWIFTSCAN_LIB" : "/this/is/a/bad/path"],
                    buildSystem: data.buildSystem,
                )
                if data.buildSystem == .native {
                    let errors = stderr.components(separatedBy: .newlines).filter { !$0.contains("[logging] misuse") && !$0.isEmpty }
                        .filter { !$0.contains("Unable to locate libSwiftScan") }
                    #expect(errors == [])
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }
}
