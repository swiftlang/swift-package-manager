/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TestSupport
import Basic
import struct Commands.Destination
import PackageModel
import Utility
import libc
import class Foundation.ProcessInfo

typealias ProcessID = Basic.Process.ProcessID

class MiscellaneousTestCase: XCTestCase {

    private var dynamicLibraryExtension: String {
        return Destination.hostDynamicLibraryExtension
    }

    func testPrintsSelectedDependencyVersion() {

        // verifies the stdout contains information about
        // the selected version of the package

        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let output = try executeSwiftBuild(prefix.appending(component: "Bar"))
            XCTAssertTrue(output.contains("Resolving"))
            XCTAssertTrue(output.contains("at 1.2.3"))
        }
    }

    func testPackageWithNoSources() throws {
        // Tests that a package with no source files doesn't error.
        fixture(name: "Miscellaneous/Empty") { prefix in
            let output = try executeSwiftBuild(prefix, configuration: .Debug)
            let expected = "warning: The target Empty in package Empty does not contain any valid source files."
            XCTAssert(output.contains(expected), "unexpected output: \(output)")
        }
    }

    func testPackageWithNoSourcesButDependency() throws {
        // Tests a package with no source files but a dependency.
        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            let output = try executeSwiftBuild(prefix.appending(component: "EmptyWithDependency"))
            let expected = "warning: The target EmptyWithDependency in package EmptyWithDependency does not contain any valid source files."
            XCTAssert(output.contains(expected), "unexpected output: \(output)")
            // We should only build the modules that are needed to be built. If
            // we have a dependency package but no way to reach some module in
            // that package, we shouldn't waste time building that.
            XCTAssertFalse(isFile(prefix.appending(components: "EmptyWithDependency", ".build", "debug", "FooLib2.swiftmodule")))
        }
    }

    func testPackageWithEmptyDependency() throws {
        // Tests a package with an empty dependency fails (we only allow it in the root package).
        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuildFails(prefix.appending(component: "HasEmptyDependency"))
        }
    }

    func testManifestExcludes1() {

        // Tests exclude syntax where no target customization is specified

        fixture(name: "Miscellaneous/ExcludeDiagnostic1") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "BarLib.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "FooBarLib.swiftmodule"))
            XCTAssertNoSuchPath(prefix.appending(components: ".build", "debug", "FooLib.swiftmodule"))
        }
    }

    func testManifestExcludes2() {

        // Tests exclude syntax where target customization is also specified
        // Refs: https://github.com/apple/swift-package-manager/pull/83

        fixture(name: "Miscellaneous/ExcludeDiagnostic2") { prefix in
            XCTAssertBuildFails(prefix)
        }
    }

    func testManifestExcludes3() {

        // Tests exclude syntax for dependencies
        // Refs: https://bugs.swift.org/browse/SR-688

        fixture(name: "Miscellaneous/ExcludeDiagnostic3") { prefix in
            XCTAssertBuilds(prefix.appending(component: "App"))
            let buildDir = prefix.appending(components: "App", ".build", "debug")
            XCTAssertFileExists(buildDir.appending(component: "App"))
            XCTAssertFileExists(buildDir.appending(component: "top"))
            XCTAssertFileExists(buildDir.appending(component: "bottom.swiftmodule"))
            XCTAssertNoSuchPath(buildDir.appending(component: "some"))
        }
    }

    func testManifestExcludes4() {

        // exclude directory is inside Tests folder (Won't build without exclude)

        fixture(name: "Miscellaneous/ExcludeDiagnostic4") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "FooPackage.swiftmodule"))
        }
    }

    func testManifestExcludes5() {

        // exclude directory is Tests folder (Won't build without exclude)

        fixture(name: "Miscellaneous/ExcludeDiagnostic5") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "FooPackage.swiftmodule"))
        }
    }

    func testPassExactDependenciesToBuildCommand() {

        // regression test to ensure that dependencies of other dependencies
        // are not passed into the build-command.

        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuilds(prefix.appending(component: "app"))
            let buildDir = prefix.appending(components: "app", ".build", "debug")
            XCTAssertFileExists(buildDir.appending(component: "FooExec"))
            XCTAssertFileExists(buildDir.appending(component: "FooLib1.swiftmodule"))
            XCTAssertFileExists(buildDir.appending(component: "FooLib2.swiftmodule"))
        }
    }

    func testCanBuildMoreThanTwiceWithExternalDependencies() {

        // running `swift build` multiple times should not fail
        // subsequent executions to an unmodified source tree
        // should immediately exit with exit-status: `0`

        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix.appending(component: "app"))
            XCTAssertBuilds(prefix.appending(component: "app"))
            XCTAssertBuilds(prefix.appending(component: "app"))
        }
    }

    func testNoArgumentsExitsWithOne() {
        var foo = false
        do {
            try executeSwiftBuild(AbsolutePath("/"))
        } catch SwiftPMProductError.executionFailure(let error, _, _) {
            switch error {
            case ProcessResult.Error.nonZeroExit(let result):
                // if our code crashes we'll get an exit code of 256
                XCTAssertEqual(result.exitStatus, .terminated(code: 1))
                foo = true
            default:
                XCTFail()
            }
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertTrue(foo)
    }

    func testCompileFailureExitsGracefully() {
        fixture(name: "Miscellaneous/CompileFails") { prefix in
            var foo = false
            do {
                try executeSwiftBuild(prefix)
            } catch SwiftPMProductError.executionFailure(let error, _, _) {
                switch error {
                case ProcessResult.Error.nonZeroExit(let result):
                    // if our code crashes we'll get an exit code of 256
                    XCTAssertEqual(result.exitStatus, .terminated(code: 1))
                    foo = true
                default:
                    XCTFail()
                }
            } catch {
                XCTFail()
            }

            XCTAssertTrue(foo)
        }
    }

    func testCanBuildIfADependencyAlreadyCheckedOut() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            try systemQuietly(Git.tool, "clone", prefix.appending(component: "deck-of-playing-cards").asString, prefix.appending(components: "app", "Packages", "DeckOfPlayingCards-1.2.3").asString)
            XCTAssertBuilds(prefix.appending(component: "app"))
        }
    }

    func testCanBuildIfADependencyClonedButThenAborted() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            try systemQuietly(Git.tool, "clone", prefix.appending(component: "deck-of-playing-cards").asString, prefix.appending(components: "app", "Packages", "DeckOfPlayingCards").asString)
            XCTAssertBuilds(prefix.appending(component: "app"), configurations: [.Debug])
        }
    }

    // if HEAD of the default branch has no Package.swift it is still
    // valid provided the selected version tag has a Package.swift
    func testTipHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = prefix.appending(component: "FisherYates")

            // required for some Linux configurations
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.email", "example@example.com")
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.name", "Example Example")

            try systemQuietly(Git.tool, "-C", path.asString, "rm", "Package.swift")
            try systemQuietly(Git.tool, "-C", path.asString, "commit", "-mwip")

            XCTAssertBuilds(prefix.appending(component: "app"))
        }
    }

    // if a tag does not have a valid Package.swift, the build fails
    func testFailsIfVersionTagHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = prefix.appending(component: "FisherYates")

            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.email", "example@example.com")
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.name", "Example McExample")
            try systemQuietly(Git.tool, "-C", path.asString, "rm", "Package.swift")
            try systemQuietly(Git.tool, "-C", path.asString, "commit", "--message", "wip")
            try systemQuietly(Git.tool, "-C", path.asString, "tag", "--force", "1.2.3")

            XCTAssertBuildFails(prefix.appending(component: "app"))
        }
    }

    func testPackageManagerDefine() {
        fixture(name: "Miscellaneous/-DSWIFT_PACKAGE") { prefix in
            XCTAssertBuilds(prefix)
        }
    }

    /**
     Tests that modules that are rebuilt causes
     any executables that link to that module to be relinked.
    */
    func testInternalDependencyEdges() {
        fixture(name: "Miscellaneous/DependencyEdges/Internal") { prefix in
            let execpath = prefix.appending(components: ".build", "debug", "Foo").asString

            XCTAssertBuilds(prefix)
            var output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            try localFileSystem.writeFileContents(prefix.appending(components: "Bar", "Bar.swift"), bytes: "public let bar = \"Goodbye\"\n")

            XCTAssertBuilds(prefix)
            output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables that link to that module in the root package.
    */
    func testExternalDependencyEdges1() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let execpath = prefix.appending(components: "app", ".build", "debug", "Dealer").asString

            let packageRoot = prefix.appending(component: "app")
            XCTAssertBuilds(packageRoot)
            var output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            let path = try SwiftPMProduct.packagePath(for: "FisherYates", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "src", "Fisher-Yates_Shuffle.swift"), bytes: "public extension Collection{ func shuffle() -> [Iterator.Element] {return []} }\n\npublic extension MutableCollection where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerated() { self[i] = self[0] } }}\n\npublic let shuffle = true")

            XCTAssertBuilds(prefix.appending(component: "app"))
            output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables for another external package to be rebuilt.
     */
    func testExternalDependencyEdges2() {
        fixture(name: "Miscellaneous/DependencyEdges/External") { prefix in
            let execpath = [prefix.appending(components: "root", ".build", "debug", "dep2").asString]

            let packageRoot = prefix.appending(component: "root")
            XCTAssertBuilds(prefix.appending(component: "root"))
            var output = try Process.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            let path = try SwiftPMProduct.packagePath(for: "dep1", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "Foo.swift"), bytes: "public let foo = \"Goodbye\"")

            XCTAssertBuilds(prefix.appending(component: "root"))
            output = try Process.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }

    func testProducts() {
        fixture(name: "Products/StaticLibrary") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "libProductName.a"))
        }
        fixture(name: "Products/DynamicLibrary") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "libProductName.\(dynamicLibraryExtension)"))
        }
    }

    func testProductWithNoModules() {
        fixture(name: "Miscellaneous/ProductWithNoModules") { prefix in
            XCTAssertBuildFails(prefix)
        }
    }

    func testProductWithMissingModules() {
        fixture(name: "Miscellaneous/ProductWithMissingModules") { prefix in
            XCTAssertBuildFails(prefix)
        }
    }

    func testSpaces() {
        fixture(name: "Miscellaneous/Spaces Fixture") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "Module_Name_1.build", "Foo.swift.o"))
        }
    }

    func testSecondBuildIsNullInModulemapGen() throws {
        // Make sure that swiftpm doesn't rebuild second time if the modulemap is being generated.
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            var output = try executeSwiftBuild(prefix, printIfError: true)
            XCTAssertFalse(output.isEmpty)
            output = try executeSwiftBuild(prefix, printIfError: true)
            XCTAssertTrue(output.isEmpty)
        }
    }

    func testSwiftTestParallel() throws {
        // Running swift-test fixtures on linux is not yet possible.
      #if os(macOS)
        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            // First try normal serial testing.
            var output = try SwiftPMProduct.SwiftTest.execute([], packagePath: prefix, printIfError: true)
            XCTAssert(output.contains("Executed 2 tests"))
            // Run tests in parallel.
            output = try SwiftPMProduct.SwiftTest.execute(["--parallel"], packagePath: prefix, printIfError: true)
            XCTAssert(output.contains("testExample2"))
            XCTAssert(output.contains("testExample1"))
            XCTAssert(output.contains("100%"))
        }
      #endif
    }

    func testSwiftTestFilter() throws {
        #if os(macOS)
            fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
                let output = try SwiftPMProduct.SwiftTest.execute(["--filter", ".*1"], packagePath: prefix, printIfError: true)
                XCTAssert(output.contains("testExample1"))
            }
        #endif
    }

    func testExecutableAsBuildOrderDependency() throws {
        // Test that we can build packages which have modules depending on executable modules.
        fixture(name: "Miscellaneous/ExecDependency") { prefix in
            XCTAssertBuilds(prefix)
        }
    }

    func testOverridingSwiftcArguments() throws {
#if os(macOS)
        fixture(name: "Miscellaneous/OverrideSwiftcArgs") { prefix in
            try executeSwiftBuild(prefix, printIfError: true, Xswiftc: ["-target", "x86_64-apple-macosx10.20"])
        }
#endif
    }

    func testPkgConfigClangModules() throws {
        fixture(name: "Miscellaneous/PkgConfig") { prefix in
            let systemModule = prefix.appending(component: "SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let output =  systemModule.appending(component: "libSystemModule.\(dynamicLibraryExtension)")
            try systemQuietly(["clang", "-shared", input.asString, "-o", output.asString])

            let pcFile = prefix.appending(component: "libSystemModule.pc")

            let stream = BufferedOutputByteStream()
            stream <<< "prefix=\(systemModule.asString)\n"
            stream <<< "exec_prefix=${prefix}\n"
            stream <<< "libdir=${exec_prefix}\n"
            stream <<< "includedir=${prefix}/Sources/include\n"
            stream <<< "Name: SystemModule\n"
            stream <<< "URL: http://127.0.0.1/\n"
            stream <<< "Description: The one and only SystemModule\n"
            stream <<< "Version: 1.10.0\n"
            stream <<< "Cflags: -I${includedir}\n"
            stream <<< "Libs: -L${libdir} -lSystemModule\n"
            try localFileSystem.writeFileContents(pcFile, bytes: stream.bytes)

            let moduleUser = prefix.appending(component: "SystemModuleUserClang")
            let env = ["PKG_CONFIG_PATH": prefix.asString]
            _ = try executeSwiftBuild(moduleUser, env: env)

            XCTAssertFileExists(moduleUser.appending(components: ".build", "debug", "SystemModuleUserClang"))
        }
    }

    func testCanKillSubprocessOnSigInt() throws {
        // <rdar://problem/31890371> swift-pm: Spurious? failures of MiscellaneousTestCase.testCanKillSubprocessOnSigInt on linux
      #if false
        fixture(name: "DependencyResolution/External/Simple") { prefix in

            let fakeGit = prefix.appending(components: "bin", "git")
            let waitFile = prefix.appending(components: "waitfile")

            try localFileSystem.createDirectory(fakeGit.parentDirectory)

            // Write out fake git.
            let stream = BufferedOutputByteStream()
            stream <<< "#!/bin/sh" <<< "\n"
            stream <<< "set -e" <<< "\n"
            stream <<< "printf \"$$\" >> " <<< waitFile.asString <<< "\n"
            stream <<< "while true; do sleep 1; done" <<< "\n"
            try localFileSystem.writeFileContents(fakeGit, bytes: stream.bytes)

            // Make it executable.
            _ = try Process.popen(args: "chmod", "+x", fakeGit.asString)

            // Put fake git in PATH.
            var env = ProcessInfo.processInfo.environment
            let oldPath = env["PATH"]
            env["PATH"] = fakeGit.parentDirectory.asString
            if let oldPath = oldPath {
                env["PATH"] = env["PATH"]! + ":" + oldPath
            }

            // Launch swift-build.
            let app = prefix.appending(component: "Bar")
            let process = Process(args: SwiftPMProduct.SwiftBuild.path.asString, "--package-path", app.asString, environment: env)
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
            let contents = try localFileSystem.readFileContents(waitFile).asString!
            XCTAssertFalse(try Process.running(process.processID))
            XCTAssertFalse(try Process.running(ProcessID(contents)!))
        }
      #endif
    }

    func testReportingErrorFromGitCommand() throws {
        fixture(name: "Miscellaneous/MissingDependency") { prefix in
            // This fixture has a setup that is intentionally missing a local
            // dependency to induce a failure.

            // Launch swift-build.
            let app = prefix.appending(component: "Bar")
            let process = Process(args: SwiftPMProduct.SwiftBuild.path.asString, "--package-path", app.asString)
            try process.launch()

            let result = try process.waitUntilExit()
            // We should exited with a failure from the attempt to "git clone"
            // something that doesn't exist.
            XCTAssert(result.exitStatus != .terminated(code: 0))
            let output = try result.utf8stderrOutput()
            XCTAssert(output.contains("does not exist"), "Error from git was not propogated to process output: \(output)")
        }
    }

    static var allTests = [
        ("testExecutableAsBuildOrderDependency", testExecutableAsBuildOrderDependency),
        ("testPrintsSelectedDependencyVersion", testPrintsSelectedDependencyVersion),
        ("testPackageWithNoSources", testPackageWithNoSources),
        ("testPackageWithNoSourcesButDependency", testPackageWithNoSourcesButDependency),
        ("testPackageWithEmptyDependency", testPackageWithEmptyDependency),
        ("testManifestExcludes1", testManifestExcludes1),
        ("testManifestExcludes2", testManifestExcludes2),
        ("testManifestExcludes3", testManifestExcludes3),
        ("testManifestExcludes4", testManifestExcludes4),
        ("testManifestExcludes5", testManifestExcludes5),
        ("testPassExactDependenciesToBuildCommand", testPassExactDependenciesToBuildCommand),
        ("testCanBuildMoreThanTwiceWithExternalDependencies", testCanBuildMoreThanTwiceWithExternalDependencies),
        ("testNoArgumentsExitsWithOne", testNoArgumentsExitsWithOne),
        ("testCompileFailureExitsGracefully", testCompileFailureExitsGracefully),
        ("testCanBuildIfADependencyAlreadyCheckedOut", testCanBuildIfADependencyAlreadyCheckedOut),
        ("testCanBuildIfADependencyClonedButThenAborted", testCanBuildIfADependencyClonedButThenAborted),
        ("testTipHasNoPackageSwift", testTipHasNoPackageSwift),
        ("testFailsIfVersionTagHasNoPackageSwift", testFailsIfVersionTagHasNoPackageSwift),
        ("testPackageManagerDefine", testPackageManagerDefine),
        ("testInternalDependencyEdges", testInternalDependencyEdges),
        ("testExternalDependencyEdges1", testExternalDependencyEdges1),
        ("testExternalDependencyEdges2", testExternalDependencyEdges2),
        ("testProducts", testProducts),
        ("testProductWithNoModules", testProductWithNoModules),
        ("testProductWithMissingModules", testProductWithMissingModules),
        ("testSpaces", testSpaces),
        ("testSecondBuildIsNullInModulemapGen", testSecondBuildIsNullInModulemapGen),
        ("testSwiftTestParallel", testSwiftTestParallel),
        ("testSwiftTestFilter", testSwiftTestFilter),
        ("testOverridingSwiftcArguments", testOverridingSwiftcArguments),
        ("testPkgConfigClangModules", testPkgConfigClangModules),
        ("testCanKillSubprocessOnSigInt", testCanKillSubprocessOnSigInt),
        ("testReportingErrorFromGitCommand", testReportingErrorFromGitCommand),
    ]
}
