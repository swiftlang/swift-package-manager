/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import SPMTestSupport
import TSCBasic
import PackageModel
import TSCUtility
import TSCLibc
import class Foundation.ProcessInfo
import class Foundation.Thread
import SourceControl
import SPMTestSupport
import Workspace

typealias ProcessID = TSCBasic.Process.ProcessID

class MiscellaneousTestCase: XCTestCase {

    func testPrintsSelectedDependencyVersion() {

        // verifies the stdout contains information about
        // the selected version of the package

        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let (output, _) = try executeSwiftBuild(prefix.appending(component: "Bar"))
            XCTAssertMatch(output, .regex("Resolving .* at 1\\.2\\.3"))
            XCTAssertMatch(output, .contains("Compiling Foo Foo.swift"))
            XCTAssertMatch(output, .contains("Merging module Foo"))
            XCTAssertMatch(output, .contains("Compiling Bar main.swift"))
            XCTAssertMatch(output, .contains("Merging module Bar"))
            XCTAssertMatch(output, .contains("Linking Bar"))
        }
    }

    func testPassExactDependenciesToBuildCommand() {

        // regression test to ensure that dependencies of other dependencies
        // are not passed into the build-command.

        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuilds(prefix.appending(component: "app"))
            let buildDir = prefix.appending(components: "app", ".build", Resources.default.toolchain.triple.tripleString, "debug")
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
            do {
                try executeSwiftBuild(prefix)
                XCTFail()
            } catch SwiftPMProductError.executionFailure(let error, let output, let stderr) {
                XCTAssertMatch(stderr + output, .contains("Compiling CompileFails Foo.swift"))
                XCTAssertMatch(stderr + output, .regex("error: .*\n.*compile_failure"))

                if case ProcessResult.Error.nonZeroExit(let result) = error {
                    // if our code crashes we'll get an exit code of 256
                    XCTAssertEqual(result.exitStatus, .terminated(code: 1))
                } else {
                    XCTFail("\(stderr + output)")
                }
            } catch {
                XCTFail()
            }
        }
    }

    func testPackageManagerDefineAndXArgs() {
        fixture(name: "Miscellaneous/-DSWIFT_PACKAGE") { prefix in
            XCTAssertBuildFails(prefix)
            XCTAssertBuilds(prefix, Xcc: ["-DEXTRA_C_DEFINE=2"], Xswiftc: ["-DEXTRA_SWIFTC_DEFINE"])
        }
    }

    /**
     Tests that modules that are rebuilt causes
     any executables that link to that module to be relinked.
    */
    func testInternalDependencyEdges() {
        fixture(name: "Miscellaneous/DependencyEdges/Internal") { prefix in
            let execpath = prefix.appending(components: ".build", Resources.default.toolchain.triple.tripleString, "debug", "Foo").pathString

            XCTAssertBuilds(prefix)
            var output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            Thread.sleep(forTimeInterval: 1)

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
            let execpath = prefix.appending(components: "app", ".build", Resources.default.toolchain.triple.tripleString, "debug", "Dealer").pathString

            let packageRoot = prefix.appending(component: "app")
            XCTAssertBuilds(packageRoot)
            var output = try Process.checkNonZeroExit(args: execpath)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            Thread.sleep(forTimeInterval: 1)

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
            let execpath = [prefix.appending(components: "root", ".build", Resources.default.toolchain.triple.tripleString, "debug", "dep2").pathString]

            let packageRoot = prefix.appending(component: "root")
            XCTAssertBuilds(prefix.appending(component: "root"))
            var output = try Process.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            Thread.sleep(forTimeInterval: 1)

            let path = try SwiftPMProduct.packagePath(for: "dep1", packageRoot: packageRoot)
            try localFileSystem.chmod(.userWritable, path: path, options: [.recursive])
            try localFileSystem.writeFileContents(path.appending(components: "Foo.swift"), bytes: "public let foo = \"Goodbye\"")

            XCTAssertBuilds(prefix.appending(component: "root"))
            output = try Process.checkNonZeroExit(arguments: execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }

    func testSpaces() {
        fixture(name: "Miscellaneous/Spaces Fixture") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", Resources.default.toolchain.triple.tripleString, "debug", "Module_Name_1.build", "Foo.swift.o"))
        }
    }

    func testSecondBuildIsNullInModulemapGen() throws {
        // This has been failing on the Swift CI sometimes, need to investigate.
      #if false
        // Make sure that swiftpm doesn't rebuild second time if the modulemap is being generated.
        fixture(name: "CFamilyTargets/SwiftCMixed") { prefix in
            var output = try executeSwiftBuild(prefix)
            XCTAssertFalse(output.isEmpty, output)
            output = try executeSwiftBuild(prefix)
            XCTAssertTrue(output.isEmpty, output)
        }
      #endif
    }

    func testSwiftTestParallel() throws {
        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
          // First try normal serial testing.
          do {
            _ = try SwiftPMProduct.SwiftTest.execute(["--enable-test-discovery"], packagePath: prefix)
          } catch SwiftPMProductError.executionFailure(_, let output, let stderr) {
            #if os(macOS)
              XCTAssertTrue(stderr.contains("Executed 2 tests"))
            #else
              XCTAssertTrue(output.contains("Executed 2 tests"))
            #endif
          }

          do {
            // Run tests in parallel.
            _ = try SwiftPMProduct.SwiftTest.execute(["--parallel", "--enable-test-discovery"], packagePath: prefix)
          } catch SwiftPMProductError.executionFailure(_, let output, _) {
            XCTAssert(output.contains("testExample1"))
            XCTAssert(output.contains("testExample2"))
            XCTAssert(!output.contains("'ParallelTestsTests' passed"))
            XCTAssert(output.contains("'ParallelTestsFailureTests' failed"))
            XCTAssert(output.contains("[3/3]"))
          }

          let xUnitOutput = prefix.appending(component: "result.xml")
          do {
            // Run tests in parallel with verbose output.
            _ = try SwiftPMProduct.SwiftTest.execute(
                ["--parallel", "--verbose", "--xunit-output", xUnitOutput.pathString, "--enable-test-discovery"],
                packagePath: prefix)
          } catch SwiftPMProductError.executionFailure(_, let output, _) {
            XCTAssert(output.contains("testExample1"))
            XCTAssert(output.contains("testExample2"))
            XCTAssert(output.contains("'ParallelTestsTests' passed"))
            XCTAssert(output.contains("'ParallelTestsFailureTests' failed"))
            XCTAssert(output.contains("[3/3]"))
          }

          // Check the xUnit output.
          XCTAssertTrue(localFileSystem.exists(xUnitOutput))
          let contents = try localFileSystem.readFileContents(xUnitOutput).description
          XCTAssertTrue(contents.contains("tests=\"3\" failures=\"1\""))
        }
    }

    func testSwiftTestFilter() throws {
        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let (stdout, _) = try SwiftPMProduct.SwiftTest.execute(["--filter", ".*1", "-l", "--enable-test-discovery"], packagePath: prefix)
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
        }

        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let (stdout, _) = try SwiftPMProduct.SwiftTest.execute(["--filter", "ParallelTestsTests", "--skip", ".*1", "--filter", "testSureFailure", "-l", "--enable-test-discovery"], packagePath: prefix)
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testSureFailure"))
        }
    }

    func testSwiftTestSkip() throws {
        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let (stdout, _) = try SwiftPMProduct.SwiftTest.execute(["--skip", "ParallelTestsTests", "-l", "--enable-test-discovery"], packagePath: prefix)
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testSureFailure"))
        }

        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let (stdout, _) = try SwiftPMProduct.SwiftTest.execute(["--filter", "ParallelTestsTests", "--skip", ".*2", "--filter", "TestsFailure", "--skip", "testSureFailure", "-l", "--enable-test-discovery"], packagePath: prefix)
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
        }

        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let (stdout, stderr) = try SwiftPMProduct.SwiftTest.execute(["--skip", "Tests", "--enable-test-discovery"], packagePath: prefix)
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
            XCTAssertMatch(stderr, .contains("No matching test cases were run"))
        }
    }

    func testOverridingSwiftcArguments() throws {
      #if os(macOS)
        fixture(name: "Miscellaneous/OverrideSwiftcArgs") { prefix in
            try executeSwiftBuild(prefix, Xswiftc: ["-target", "x86_64-apple-macosx10.20"])
        }
      #endif
    }

    func testPkgConfigCFamilyTargets() throws {
        fixture(name: "Miscellaneous/PkgConfig") { prefix in
            let systemModule = prefix.appending(component: "SystemModule")
            // Create a shared library.
            let input = systemModule.appending(components: "Sources", "SystemModule.c")
            let triple = Resources.default.toolchain.triple
            let output =  systemModule.appending(component: "libSystemModule\(triple.dynamicLibraryExtension)")
            try systemQuietly(["clang", "-shared", input.pathString, "-o", output.pathString])

            let pcFile = prefix.appending(component: "libSystemModule.pc")

            let stream = BufferedOutputByteStream()
            stream <<< """
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
            try localFileSystem.writeFileContents(pcFile, bytes: stream.bytes)

            let moduleUser = prefix.appending(component: "SystemModuleUserClang")
            let env = ["PKG_CONFIG_PATH": prefix.pathString]
            _ = try executeSwiftBuild(moduleUser, env: env)

            XCTAssertFileExists(moduleUser.appending(components: ".build", triple.tripleString, "debug", "SystemModuleUserClang"))
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
            stream <<< """
                #!/bin/sh
                set -e
                printf "$$" >> \(waitFile)
                while true; do sleep 1; done

                """
            try localFileSystem.writeFileContents(fakeGit, bytes: stream.bytes)

            // Make it executable.
            _ = try Process.popen(args: "chmod", "+x", fakeGit.description)

            // Put fake git in PATH.
            var env = ProcessInfo.processInfo.environment
            let oldPath = env["PATH"]
            env["PATH"] = fakeGit.parentDirectory.description
            if let oldPath = oldPath {
                env["PATH"] = env["PATH"]! + ":" + oldPath
            }

            // Launch swift-build.
            let app = prefix.appending(component: "Bar")
            let process = Process(args: SwiftPMProduct.SwiftBuild.path.description, "--package-path", app.description, environment: env)
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
            let contents = try localFileSystem.readFileContents(waitFile).description
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

            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: app)

            // We should exited with a failure from the attempt to "git clone"
            // something that doesn't exist.
            XCTAssert(result.exitStatus != .terminated(code: 0))
            let output = try result.utf8stderrOutput()
            XCTAssert(output.contains("does not exist"), "Error from git was not propogated to process output: \(output)")
        }
    }

    func testSwiftTestLinuxMainGeneration() throws {
      #if os(macOS)
        fixture(name: "Miscellaneous/ParallelTestsPkg") { prefix in
            let fs = localFileSystem
            try SwiftPMProduct.SwiftTest.execute(["--generate-linuxmain"], packagePath: prefix)

            // Check linux main.
            let linuxMain = prefix.appending(components: "Tests", "LinuxMain.swift")
            XCTAssertEqual(try fs.readFileContents(linuxMain), """
                import XCTest

                import ParallelTestsPkgTests

                var tests = [XCTestCaseEntry]()
                tests += ParallelTestsPkgTests.__allTests()

                XCTMain(tests)

                """)

            // Check test manifest.
            let testManifest = prefix.appending(components: "Tests", "ParallelTestsPkgTests", "XCTestManifests.swift")
            XCTAssertEqual(try fs.readFileContents(testManifest), """
                #if !canImport(ObjectiveC)
                import XCTest

                extension ParallelTestsFailureTests {
                    // DO NOT MODIFY: This is autogenerated, use:
                    //   `swift test --generate-linuxmain`
                    // to regenerate.
                    static let __allTests__ParallelTestsFailureTests = [
                        ("testSureFailure", testSureFailure),
                    ]
                }

                extension ParallelTestsTests {
                    // DO NOT MODIFY: This is autogenerated, use:
                    //   `swift test --generate-linuxmain`
                    // to regenerate.
                    static let __allTests__ParallelTestsTests = [
                        ("testExample1", testExample1),
                        ("testExample2", testExample2),
                    ]
                }

                public func __allTests() -> [XCTestCaseEntry] {
                    return [
                        testCase(ParallelTestsFailureTests.__allTests__ParallelTestsFailureTests),
                        testCase(ParallelTestsTests.__allTests__ParallelTestsTests),
                    ]
                }
                #endif

                """)
        }
      #endif
    }

    func testUnicode() {
        #if !os(Linux) && !os(Android) // TODO: - Linux has trouble with this and needs investigation.
        fixture(name: "Miscellaneous/Unicode") { prefix in
            // See the fixture manifest for an explanation of this string.
            let complicatedString = "πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄"
            let verify = "\u{03C0}\u{0FB2C}\u{00B5}\u{1D11E}\u{1F1FA}\u{1F1F3}\u{1F1EE}\u{1F1F1}\u{0078}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}\u{0331}\u{0304}"
            XCTAssert(
                complicatedString.unicodeScalars.elementsEqual(verify.unicodeScalars),
                "\(complicatedString) ≠ \(verify)")

            // ••••• Set up dependency.
            let dependencyName = "UnicodeDependency‐\(complicatedString)"
            let dependencyOrigin = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory
                .appending(component: "Fixtures")
                .appending(component: "Miscellaneous")
                .appending(component: dependencyName)
            let dependencyDestination = prefix.parentDirectory.appending(component: dependencyName)
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
            try SwiftPMProduct.SwiftTest.execute([], packagePath: prefix)
            try SwiftPMProduct.SwiftRun.execute([complicatedString + "‐tool"], packagePath: prefix)
        }
        #endif
    }

    func testTrivialSwiftAPIDiff() throws {
        // FIXME: Looks like this test isn't really working at all.
        guard Resources.havePD4Runtime else { return }

        if (try? Resources.default.toolchain.getSwiftAPIDigester()) == nil {
            print("unable to find swift-api-digester, skipping \(#function)")
            return
        }

        mktmpdir { path in
            let fs = localFileSystem

            let package = path.appending(component: "foo")
            try fs.createDirectory(package)

            try SwiftPMProduct.SwiftPackage.execute(["init"], packagePath: package)

            let foo = package.appending(components: "Sources", "foo", "foo.swift")
            try fs.writeFileContents(foo) {
                $0 <<< """
                public struct Foo {
                    public func foo() -> String { fatalError() }
                }
                """
            }

            initGitRepo(package, tags: ["1.0.0"])

            try fs.writeFileContents(foo) {
                $0 <<< """
                public struct Foo {
                    public func foo(param: Bool = true) -> Int { fatalError() }
                }
                """
            }

            let (diff, _) = try SwiftPMProduct.SwiftPackage.execute(["experimental-api-diff", "1.0.0"], packagePath: package)
            XCTAssertMatch(diff, .contains("Func Foo.foo() has been renamed to Func foo(param:)"))
            XCTAssertMatch(diff, .contains("Func Foo.foo() has return type change from Swift.String to Swift.Int"))
        }
    }
}
