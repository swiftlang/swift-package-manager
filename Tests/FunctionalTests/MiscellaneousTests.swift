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
import SPMBuildCore
import _InternalTestSupport
import Workspace
import Testing
import Testing

import class Basics.AsyncProcess
import struct SPMBuildCore.BuildSystemProvider
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func printsSelectedDependencyVersion(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
            let (stdout, stderr) = try await executeSwiftBuild(
                fixturePath.appending("Bar"),
                configuration: config,
                buildSystem: buildSystem,
            )
            // package resolution output goes to stderr
            let packageRegex = try Regex("Computed .* at 1\\.2\\.3")
            #expect(stderr.contains(packageRegex))
            // in "swift build" build output goes to stdout
            if buildSystem == .native {
                #expect(stdout.contains("Compiling Foo Foo.swift"))
                #expect(stdout.contains("Compiling Bar main.swift"))
                if (config == .debug) {
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func passExactDependenciesToBuildCommand(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/ExactDependencies") { fixturePath in
            let packagePath = fixturePath.appending("app")
            try await executeSwiftBuild(
                packagePath,
                configuration: config,
                buildSystem: buildSystem,
            )
            let buildDir = try packagePath.appending(components: buildSystem.binPath(for: config))
            expectFileExists(at: buildDir.appending(executableName("FooExec")))
            if buildSystem == .native {
                expectFileExists(at: buildDir.appending(components: "Modules", "FooLib1.swiftmodule"))
                expectFileExists(at: buildDir.appending(components: "Modules", "FooLib2.swiftmodule"))
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func canBuildMoreThanTwiceWithExternalDependencies(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: config,
                buildSystem: buildSystem,
            )
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: config,
                buildSystem: buildSystem,
            )
            try await executeSwiftBuild(
                fixturePath.appending("app"),
                configuration: config,
                buildSystem: buildSystem,
            )
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func noArgumentsExitsWithOne(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        await expectThrowsCommandExecutionError(
            try await executeSwiftBuild(
                "/",
                configuration: config,
                buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func compileFailureExitsGracefully(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/CompileFails") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            ) { error in
                // if our code crashes we'll get an exit code of 256
                guard error.result.exitStatus == .terminated(code: 1) else {
                    Issue.record("failed in an unexpected manner: \(error)")
                    return
                }
                if buildSystem == .native {
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func packageManagerDefineAndXArgs(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/-DSWIFT_PACKAGE") { fixturePath in
            await #expect(throws: SwiftPMError.self) {
                try await executeSwiftBuild(
                    fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                )
            }
            try await withKnownIssue(isIntermittent: true) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    Xcc: ["-DEXTRA_C_DEFINE=2"],
                    Xswiftc: ["-DEXTRA_SWIFTC_DEFINE"],
                    buildSystem: buildSystem,
                )
            } when: {
                buildSystem == .swiftbuild
            }
        }
    }

    /**
     Tests that modules that are rebuilt causes
     any executables that link to that module to be relinked.
     */
    @Test(
        .IssueWindowsFolderCreationFailure,
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func internalDependencyEdges(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "Miscellaneous/DependencyEdges/Internal") { fixturePath in
            let binPath = try fixturePath.appending(components: buildSystem.binPath(for: configuration))
            let executable = binPath.appending(components: "Foo")
            let execPath = executable.pathString

            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            try requireFileExists(at: executable)
            let output = try await AsyncProcess.checkNonZeroExit(args: execPath)
            #expect(output == "Hello\(ProcessInfo.EOL)")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            try localFileSystem.writeFileContents(fixturePath.appending(components: "Bar", "Bar.swift"), bytes: "public let bar = \"Goodbye\"\n")

            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            try requireFileExists(at: executable)
            let output2 = try await AsyncProcess.checkNonZeroExit(args: execPath)
            #expect(output2 == "Goodbye\(ProcessInfo.EOL)")
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables that link to that module in the root package.
     */
    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func externalDependencyEdges1(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue {
        try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
            let packageRoot = fixturePath.appending(component: "app")
            let binPath = try packageRoot.appending(components: buildSystem.binPath(for: configuration))
            let executable = binPath.appending(component: "Dealer")
            let execPath = executable.pathString

            try await executeSwiftBuild(
                packageRoot,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            try requireFileExists(at: executable)
            let output = try await AsyncProcess.checkNonZeroExit(args: execPath).withSwiftLineEnding
            #expect(output == "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            try await Task.sleep(for: .seconds(1))

            let path = try SwiftPM.packagePath(for: "FisherYates", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "src", "Fisher-Yates_Shuffle.swift"), bytes: "public extension Collection{ func shuffle() -> [Iterator.Element] {return []} }\n\npublic extension MutableCollection where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerated() { self[i] = self[0] } }}\n\npublic let shuffle = true")

            try await executeSwiftBuild(
                packageRoot,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            try requireFileExists(at: executable)
            let output2 = try await AsyncProcess.checkNonZeroExit(args: execPath).withSwiftLineEnding
            #expect(output2 == "♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n")
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .native && configuration == .debug)
            || (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables for another external package to be rebuilt.
     */
    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        // TODO: raise GitHub issue
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func externalDependencyEdges2(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/DependencyEdges/External") { fixturePath in
            let packageRoot = fixturePath.appending("root")
            let binPath = try packageRoot.appending(components: buildSystem.binPath(for: configuration))
            let executable = binPath.appending(component: "dep2")
            let execpath = [executable.pathString]

            try await executeSwiftBuild(
                packageRoot,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            try await withKnownIssue {
                try requireFileExists(at: executable)
                let output = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
                #expect(output == "Hello\(ProcessInfo.EOL)")

                // we need to sleep at least one second otherwise
                // llbuild does not realize the file has changed
                try await Task.sleep(for: .seconds(1))

                let path = try SwiftPM.packagePath(for: "dep1", packageRoot: packageRoot)
                try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
                try localFileSystem.writeFileContents(path.appending(components: "Foo.swift"), bytes: "public let foo = \"Goodbye\"")

                try await executeSwiftBuild(
                    packageRoot,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                try requireFileExists(at: executable)
                let output2 = try await AsyncProcess.checkNonZeroExit(arguments: execpath)
                #expect(output2 == "Goodbye\(ProcessInfo.EOL)")
            } when: {
                (ProcessInfo.hostOperatingSystem == .windows)
            }
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func packagePathContainsSpaces(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) { // might no longer be withKnownIssue, but leaving for now.
            try await fixture(name: "Miscellaneous/Spaces Fixture") { fixturePath in
                await #expect(throws: Never.self) {
                    try await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
                let binPath = try fixturePath.appending(components: buildSystem.binPath(for: configuration))
                switch buildSystem {
                    case .native:
                        expectFileExists(at: binPath.appending(components: "Module_Name_1.build", "Foo.swift.o"))
                    case .xcode, .swiftbuild:
                        break
                }
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .disabled("XCTest was disabled"),
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func secondBuildIsNullInModulemapGen(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        // Make sure that swiftpm doesn't rebuild second time if the modulemap is being generated.
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            let output = try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            ).stdout
            #expect(!output.isEmpty)
            let secondOutput = try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func overridingDeploymentTargetUsingSwiftCompilerArgument(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/DistantFutureDeploymentTarget") { fixturePath in
                let hostTriple = try UserToolchain.default.targetTriple
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    Xswiftc: ["-target", "\(hostTriple.archName)-apple-macosx41.0"],
                    buildSystem: buildSystem,
                )
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .serialized, // Because the tests set the environment variable
        // TODO: raise a GitHub issue .  the second `swift-build` command fails.
        .tags(
            .Feature.Command.Build,
        ),
        .requires(executable: executableName("clang")),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func pkgConfigCFamilyTargets(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue {
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
            let binPath = try moduleUser.appending(components: buildSystem.binPath(for: configuration))
            await withKnownIssue(isIntermittent: true) {
                await #expect(throws: Never.self) {
                    _ = try await executeSwiftBuild(
                        moduleUser,
                        configuration: configuration,
                        env: env,
                        buildSystem: buildSystem,
                    )
                }
                expectFileExists(at: binPath.appending(component: "SystemModuleUserClang"))
            } when:{
                buildSystem == .swiftbuild && configuration == .release && ProcessInfo.hostOperatingSystem != .linux
            }

            // Clean up the build directory before re-running the build with
            // different arguments.
            _ = try await executeSwiftPackage(
                moduleUser,
                configuration: configuration,
                extraArgs: ["clean"],
                buildSystem: buildSystem,
            )

            await withKnownIssue(isIntermittent: true) {
                await #expect(throws: Never.self) {
                    _ = try await executeSwiftBuild(
                        moduleUser,
                        configuration: configuration,
                        extraArgs: ["--pkg-config-path", fixturePath.pathString],
                        buildSystem: buildSystem,
                    )
                }

                expectFileExists(at: binPath.appending(component: "SystemModuleUserClang"))
            } when: {
                buildSystem == .swiftbuild
            }
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .native)
            || (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild && configuration == .debug)
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func reportingErrorFromGitCommand(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/MissingDependency") { fixturePath in
            // This fixture has a setup that is intentionally missing a local
            // dependency to induce a failure.

            // Launch swift-build.
            let app = fixturePath.appending("Bar")

            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    app,
                    configuration: configuration,
                    buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func localPackageUsedAsURLValidation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/LocalPackageAsURL", createGitRepo: false) { fixturePath in
            // This fixture has a setup that is trying to use a local package
            // as a url that hasn't been initialized as a repo
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath.appending("Bar"),
                    configuration: configuration,
                    buildSystem: buildSystem,
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
        .skipHostOS(.linux),
        .skipHostOS(.android),
        .tags(
            .Feature.Command.Test,
            .Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func unicode(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
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
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                try await withKnownIssue(isIntermittent: true) {
                    try await executeSwiftRun(
                        fixturePath,
                        complicatedString + "‐tool",
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                } when: {
                    ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .skipHostOS(.linux), // TODO: raise GitHub issue.. crashed on Linux
        // TODO: raise GitHub issue for issue on Windows
        .tags(
            .Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testsCanLinkAgainstExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true,
                )
                // in "swift test" build output goes to stderr
                switch buildSystem {
                    case .native:
                        #expect(stderr.contains("Linking TestableExe1"))
                        #expect(stderr.contains("Linking TestableExe2"))
                        #expect(stderr.contains("Linking TestableExePackageTests"))
                    case .swiftbuild, .xcode:
                        break
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
                    configuration: configuration,
                    extraArgs: ["-v"],
                    buildSystem: buildSystem,
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
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    @available(macOS 15, *)
    func testsCanLinkAgainstAsyncExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue {
        try await fixture(name: "Miscellaneous/TestableAsyncExe") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
                throwIfCommandFails: true,
            )
            // in "swift test" build output goes to stderr
            switch buildSystem {
                case .native:
                    #expect(stderr.contains("Linking TestableAsyncExe1"))
                    #expect(stderr.contains("Linking TestableAsyncExe2"))
                    #expect(stderr.contains("Linking TestableAsyncExe3"))
                    #expect(stderr.contains("Linking TestableAsyncExe4"))
                    #expect(stderr.contains("Linking TestableAsyncExePackageTests"))
                case .swiftbuild, .xcode:
                    break
            }
            #expect(stderr.contains("Build complete!"))
            // in "swift test" test output goes to stdout
            #expect(stdout.contains("Executed 1 test"), "stderr: \(stderr)")
            #expect(stdout.contains("Hello, async world"), "stderr: \(stderr)")
            #expect(stdout.contains("Hello, async planet"), "stderr: \(stderr)")
            #expect(stdout.contains("Hello, async galaxy"), "stderr: \(stderr)")
            #expect(stdout.contains("Hello, async universe"), "stderr: \(stderr)")
        }
        } when: {
            // error: FileSystemError(kind: TSCBasic.FileSystemError.Kind.noEntry, path: Optional(<AbsolutePath:"C:\Users\ContainerAdministrator\AppData\Local\Temp\Miscellaneous_TestableAsyncExe.74Koc7\Miscellaneous_TestableAsyncExe\.build\out\Intermediates.noindex\TestableAsyncExe.build\Debug-windows\TestableAsyncExe4.build\Objects-normal\x86_64\TestableAsyncExe4.LinkFileList">))
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executableTargetMismatch(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "Miscellaneous/TargetMismatch") { path in
            let (stdout, stderr) = try await executeSwiftBuild(
                path,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            // in "swift build" build output goes to stdout
            if buildSystem == .native {
                #expect(stdout.contains("Compiling Sample main.swift"))
            }
            #expect(stderr.contains("The target named 'Sample' was identified as an executable target but a non-executable product with this name already exists."))
        }
        } when: {
            // error: Unable to resolve build file: BuildFile<PACKAGE-PRODUCT:miscellaneous_targetmismatch_Sample.Sample::BUILDPHASE_0::0> (The workspace has a reference to a missing target with GUID 'PACKAGE-TARGET:Sample')
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func libraryTriesToIncludeExecutableTarget(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/PackageWithMalformedLibraryProduct") { path in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func editModeEndToEnd(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
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
                    configuration: configuration,
                    extraArgs: ["-v"],
                    buildSystem: buildSystem,
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
                configuration: configuration,
                extraArgs: ["edit", "Foo"],
                buildSystem: buildSystem,
            )
            expectDirectoryExists(at: appPath.appending(components: ["Packages", "Foo"]))

            do {
                // build again in edit mode
                let output = try await executeSwiftBuild(
                    appPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(output.stdout.contains("Build complete!"))
            }

            do {
                // take foo out of edit mode
                let output = try await executeSwiftPackage(
                    appPath,
                    configuration: configuration,
                    extraArgs: ["-v", "unedit", "Foo"],
                    buildSystem: buildSystem,
                )
                // package resolution output goes to stderr
                #expect(output.stderr.contains("Creating working copy for \(prefix.appending("Foo"))"))
                expectFileDoesNotExists(at: appPath.appending(components: ["Packages", "Foo"]))
            }

            // build again in edit mode
            do {
                let output = try await executeSwiftBuild(
                    appPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
        [ "cache-path", "config-path", "security-path"],
    )
    func customCachePath(
        buildSystem: BuildSystemProvider.Kind,
        pathOption: String,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/Simple") { path in
            let customPath = path.appending(components: "custom", pathOption)
            expectFileDoesNotExists(at: customPath)
            expectDirectoryDoesNotExist(at: customPath)
            try await executeSwiftBuild(
                path,
                configuration: configuration,
                extraArgs: ["--\(pathOption)", customPath.pathString],
                buildSystem: buildSystem,
            )
            expectDirectoryExists(at: customPath)
        }
    }

    @Test(
        // .skipHostOS(.linux, "`FileSystem` does not support `chmod` on Linux"),
        // .skipHostOS(.windows, "`FileSystem` does not support `chmod` on Windows"),
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        [ "cache-path", "config-path", "security-path"],
    )
    func customPathUserUnwritableGeneratesPermissionError(
        buildSystem: BuildSystemProvider.Kind,
        pathOption: String,
    ) async throws {
        let configuration = BuildConfiguration.debug
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
            try await withKnownIssue(isIntermittent: true) {
                await expectThrowsCommandExecutionError(
                    try await executeSwiftBuild(
                        path,
                        configuration: configuration,
                        extraArgs: ["--\(pathOption)", customPath.pathString],
                        buildSystem: buildSystem,
                    )
                ) { error in
                    let stderr = error.stderr
                    #expect(stderr.contains("error: invalid access to"), "expected permissions error. stderr: '\(stderr)', stdout '\(error.stdout)'")
                }
                expectFileDoesNotExists(at: customPath)
                expectDirectoryDoesNotExist(at: customPath)
            } when: {
                ProcessInfo.hostOperatingSystem != .macOS // `FileSystem` many not support `chmod` on this host OS
            }
        }
    }


    @Test(
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func pluginGeneratedResources(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/PluginGeneratedResources") { path in
                let result = try await executeSwiftRun(
                    path,
                    nil,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(result.stdout == "Hello, World!\n")
                #expect(result.stderr.contains("Copying best.txt\n"), "build log is missing message about copying resource file")
            }
        }when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux)
            || (buildSystem == .swiftbuild)
            || (ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline)
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func compileCXX17CrashWithFModules(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/CXX17CompilerCrash/v5_8") { fixturePath in
            await #expect(throws: Never.self) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        }
    }

    @Test(
        .IssueWindowsFolderCreationFailure,
        .tags(
            .Feature.Command.Build,
        ),
        // TODO: raise GitHub issue for known issue on Windows
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func noJSONOutputWithFlatPackageStructure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "Miscellaneous/FlatPackage") { packagePath in
            // First build, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout1, stderr1) = try await executeSwiftBuild(
                packagePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let buildOutput = try packagePath.appending(components: buildSystem.binPath(for: configuration))
            expectDirectoryExists(at: buildOutput)
            #expect(!stdout1.contains("command_arguments"))
            #expect(!stderr1.contains("command_arguments"))

            // Now test, make sure we got the `.build` directory where we expect it, and that there is no JSON output (by looking for known output).
            let (stdout2, stderr2) = try await executeSwiftTest(
                packagePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let testOutput = try packagePath.appending(components: buildSystem.binPath(for: configuration))
            expectDirectoryExists(at: testOutput)
            #expect(!stdout2.contains("command_arguments"))
            #expect(!stderr2.contains("command_arguments"))
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9078", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func noWarningFromRemoteDependencies(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/DependenciesWarnings") { path in
            // prepare the deps as git sources
            let dependency1Path = path.appending("dep1")
            initGitRepo(dependency1Path, tag: "1.0.0")
            let dependency2Path = path.appending("dep2")
            initGitRepo(dependency2Path, tag: "1.0.0")

            let appPath = path.appending("app")
            let (stdout, stderr) = try await executeSwiftBuild(
                appPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let buildOutput = try appPath.appending(components: buildSystem.binPath(for: configuration))
            expectDirectoryExists(at: buildOutput)
            #expect((stdout + stderr).contains("'DeprecatedApp' is deprecated"))
            #expect(!(stdout + stderr).contains("'Deprecated1' is deprecated"))
            #expect(!(stdout + stderr).contains("'Deprecated2' is deprecated"))
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9517", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func noWarningFromRemoteDependenciesWithWarningsAsErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/DependenciesWarnings2") { path in
                // prepare the deps as git sources
                let dependency1Path = path.appending("dep1")
                initGitRepo(dependency1Path, tag: "1.0.0")
                let dependency2Path = path.appending("dep2")
                initGitRepo(dependency2Path, tag: "1.0.0")

                let appPath = path.appending("app")
                let (stdout, stderr) = try await executeSwiftBuild(
                    appPath,
                    configuration: configuration,
                    Xswiftc: ["-warnings-as-errors"],
                    buildSystem: buildSystem,
                )
                let buildOutput = try appPath.appending(components: buildSystem.binPath(for: configuration))
                expectDirectoryExists(at: buildOutput)
                #expect(!(stdout + stderr).contains("'Deprecated1' is deprecated"))
                #expect(!(stdout + stderr).contains("'Deprecated2' is deprecated"))
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .tags(
            .Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func rootPackageWithConditionals(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/RootPackageWithConditionals") { path in
                let (_, stderr) = try await executeSwiftBuild(
                    path,
                    configuration: configuration,
                    env: ["SWIFT_DRIVER_SWIFTSCAN_LIB" : "/this/is/a/bad/path"],
                    buildSystem: buildSystem,
                )
                switch buildSystem {
                    case .native:
                        let errors = stderr.components(separatedBy: .newlines).filter { !$0.contains("[logging] misuse") && !$0.isEmpty }
                                                                        .filter { !$0.contains("Unable to locate libSwiftScan") }
                        #expect(errors == [])
                    case .swiftbuild, .xcode:
                        break
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }
}

@Suite
struct MiscellaneousSwiftTestingTests {
    @Test(.skipHostOS(.windows), arguments: SupportedBuildSystemOnAllPlatforms)
    func pkgConfigCFamilyTargets(buildSystem: BuildSystemProvider.Kind) async throws {
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
            _ = try await executeSwiftBuild(
                moduleUser,
                env: env,
                buildSystem: buildSystem,
            )

            // Clean up the build directory before re-running the build with
            // different arguments.
            _ = try await executeSwiftPackage(
                moduleUser,
                extraArgs: ["clean"],
                buildSystem: buildSystem,
            )

            _ = try await executeSwiftBuild(
                moduleUser,
                extraArgs: ["--pkg-config-path", fixturePath.pathString],
                buildSystem: buildSystem,
            )
        }
    }
}
