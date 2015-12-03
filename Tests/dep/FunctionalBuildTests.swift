/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import dep
import struct PackageDescription.Version
import POSIX
import sys
import XCTest


class FunctionalBuildTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testEmptyPackageSwiftExitsWithZero", testEmptyPackageSwiftExitsWithZero),
            ("testIgnoreFiles", testIgnoreFiles),
            ("testSingleLibTarget", testSingleLibTarget),
            ("testMultipleLibTargets", testMultipleLibTargets),
            ("testSingleExecTarget", testSingleExecTarget),
            ("testMultipleExecTargets", testMultipleExecTargets),
            ("testMultipleLibAndExecTargets", testMultipleLibAndExecTargets),
            ("testSingleLibTargetInSources", testSingleLibTargetInSources),
            ("testMultipleLibTargetsInSources", testMultipleLibTargetsInSources),
            ("testSingleExecTargetInSources", testSingleExecTargetInSources),
            ("testMultipleExecTargetsInSources", testMultipleExecTargetsInSources),
            ("testMultipleLibAndExecTargetsInSources", testMultipleLibAndExecTargetsInSources),
            ("testSingleLibTargetSrc", testSingleLibTargetSrc),
            ("testMultipleLibTargetsSrc", testMultipleLibTargetsSrc),
            ("testSingleExecTargetSrc", testSingleExecTargetSrc),
            ("testMultipleExecTargetsSrc", testMultipleExecTargetsSrc),
            ("testMultipleExecTargetsSourcesSrc", testMultipleExecTargetsSourcesSrc),
            ("testMultipleLibTargetsSourcesSrc", testMultipleLibTargetsSourcesSrc),
            ("testMultipleLibExecTargetsSourcesSrc", testMultipleLibExecTargetsSourcesSrc),
            ("testMultipleLibExecTargetsSourcesSrcExt", testMultipleLibExecTargetsSourcesSrcExt),
            ("testLibDep", testLibDep),
            ("testLibDeps", testLibDeps),
            ("testExecDep", testExecDep),
            ("testExecDeps", testExecDeps),
            ("testMultDeps", testMultDeps),
            ("test_exdeps", test_exdeps),
            ("test_exdeps_canRunBuildTwice", test_exdeps_canRunBuildTwice),
            ("test_get_ExternalDeps", test_get_ExternalDeps),
            ("test_get_DealerBuild", test_get_DealerBuild),
            ("test_get_DealerBuildOutput", test_get_DealerBuildOutput),
            ("testNoArgumentsExitsWithOne", testNoArgumentsExitsWithOne),
            ("testCompileFailureExitsGracefully", testCompileFailureExitsGracefully),
            ("testDependenciesWithVPrefixTagsWork", testDependenciesWithVPrefixTagsWork),
            ("testWhenThereAreHyphensInThePath", testWhenThereAreHyphensInThePath),
            ("testSingleTargetWithCustomName", testSingleTargetWithCustomName),
            ("testCanBuildIfADependencyAlreadyCheckedOut", testCanBuildIfADependencyAlreadyCheckedOut),
            ("testCanBuildIfADependencyClonedButThenAborted", testCanBuildIfADependencyClonedButThenAborted),
        ]
    }

    func testEmptyPackageSwiftExitsWithZero() {
        fixture(name: "1_self_diagnostic") { prefix in
            XCTAssertTrue(Path.join(prefix, Manifest.filename).isFile)
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
        }
    }

    func verifyFilesExist(files: [String], fixturePath: String) -> Bool {
        for file in files {
            let name = fixturePath.characters.split("/").map(String.init).last!
            let filePath: String
            switch file {
                // Target (library) not in subfolder
            case "rootLib":
                filePath = Path.join(fixturePath, ".build/debug", "\(name).a")
                // Target (executable) not in subfolder
            case "rootExec":
                filePath = Path.join(fixturePath, ".build/debug", name)
            default:
                filePath = Path.join(fixturePath, ".build/debug", file)
            }

            guard filePath.isFile else { return false }
        }
        return true
    }

    func testIgnoreFiles() {
        fixture(name: "20_ignore_files") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))

            let targets = try! determineTargets(packageName: "foo", prefix: prefix)

            XCTAssertEqual(targets.count, 1)
            XCTAssertEqual(targets[0].sources.map({ $0.basename }), ["Foo.swift"])
        }
    }

    // 2: Package with one library target
    func testSingleLibTarget() {
        let filesToVerify = ["rootLib"]
        fixture(name: "2_buildlib_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }


    // 3: Package with multiple library targets
    func testMultipleLibTargets() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        fixture(name: "3_buildlib_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }


    // 4: Package with one executable target
    func testSingleExecTarget() {
        let filesToVerify = ["rootExec"]
        fixture(name: "4_buildexec_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 5: Package with multiple exectuble targets
    func testMultipleExecTargets() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        fixture(name: "5_buildexec_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 6: Package with multiple library and executable targets
    func testMultipleLibAndExecTargets() {
        let filesToVerify = ["BarExec", "BarFooLib.a", "FooBarLib.a", "FooExec"]
        fixture(name: "6_buildexeclib_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 7: Package with a single library target in a sources directory
    func testSingleLibTargetInSources() {
        let filesToVerify = ["rootLib"]
        fixture(name: "7_buildlib_sources_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 8: Package with multiple library targets in a sources directory
    func testMultipleLibTargetsInSources() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        fixture(name: "8_buildlib_sources_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 9: Package with a single executable target in a sources directory
    func testSingleExecTargetInSources() {
        let filesToVerify = ["rootExec"]
        fixture(name: "9_buildexec_sources_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 10: Package with multiple executable targets in a sources directory
    func testMultipleExecTargetsInSources() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        fixture(name: "10_buildexec_sources_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 11: Package with multiple library and executable targets in a sources directory
    func testMultipleLibAndExecTargetsInSources() {
        let filesToVerify = ["BarFooExec", "BarLib.a", "FooBarExec", "FooLib.a"]
        fixture(name: "11_buildexeclib_sources_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 12: Package with a single library targets in a src directory
    func testSingleLibTargetSrc() {
        let filesToVerify = ["rootLib"]
        fixture(name: "12_buildlib_src_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 13: Package with multiple library targets in a src directory
    func testMultipleLibTargetsSrc() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        fixture(name: "13_buildlib_src_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 14: Package with a single executable target in a src directory
    func testSingleExecTargetSrc() {
        let filesToVerify = ["rootExec"]
        fixture(name: "14_buildexec_src_single_target") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 15: Package with multiple executable targets in src directory
    func testMultipleExecTargetsSrc() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        fixture(name: "15_buildexec_src_mult_targets") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 16: Package with multiple executable targets in a sources and src directory
    func testMultipleExecTargetsSourcesSrc() {
        fixture(name: "16_buildexec_src_sources") { prefix in
            do {
                try executeSwiftBuild(prefix)
                XCTFail()
            } catch POSIX.Error.ExitStatus {

            } catch {
                XCTFail()
            }
        }
    }


    // 17: Package with multiple library targets in a sources and src directory
    func testMultipleLibTargetsSourcesSrc() {
        fixture(name: "17_buildlib_src_sources") { prefix in
            do {
                try executeSwiftBuild(prefix)
                XCTFail()
            } catch POSIX.Error.ExitStatus {

            } catch {
                XCTFail()
            }
        }
    }


    // 18: Package with multiple executable and library targets in a sources and src directory
    func testMultipleLibExecTargetsSourcesSrc() {
        fixture(name: "18_buildlibexec_src_sources") { prefix in
            do {
                try executeSwiftBuild(prefix)
                XCTFail()
            } catch POSIX.Error.ExitStatus {

            } catch {
                XCTFail()
            }
        }
    }


    // 19: Package with multiple executable and library targets in a sources and src directory, and externally
    func testMultipleLibExecTargetsSourcesSrcExt() {
        fixture(name: "19_buildlibexec_src_sources_external") { prefix in
            do {
                try executeSwiftBuild(prefix)
                XCTFail()
            } catch POSIX.Error.ExitStatus {

            } catch {
                XCTFail()
            }
        }
    }


    // 20: Single dependency where BarLib depends on FooLib
    func testLibDep() {
        let filesToVerify = ["BarLib.a", "FooLib.a"]
        fixture(name: "20_buildlib_singledep") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 21: Multiple dependencies where BarLib depends on FooLib and FooBarLib
    func testLibDeps() {
        let filesToVerify = ["BarLib.a", "FooLib.a", "FooBarLib.a"]
        fixture(name: "21_buildlib_multdep") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 22: Single dependency where Foo executable depends on Foo library
    func testExecDep() {
        let filesToVerify = ["FooLib.a", "FooExec"]
        fixture(name: "22_buildexec_singledep") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 23: Multiple dependencies where Foo executable depends on two libraries
    func testExecDeps() {
        let filesToVerify = ["FooExec", "FooLib1.a", "FooLib2.a"]
        fixture(name: "23_buildexec_multdep") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    // 24: Multiple dependencies
    func testMultDeps() {
        let filesToVerify = ["Bar.a", "BarLib.a", "DepOnFooExec", "DepOnFooLib.a", "Foo", "FooLib.a"]
        fixture(name: "24_buildexeclib_deps") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(filesToVerify, fixturePath: prefix))
        }
    }

    func test_exdeps() {
        fixture(name: "102_mattts_dealer") { prefix in
            let prefix = Path.join(prefix, "app")
            try executeSwiftBuild(prefix)
        }
    }

    func test_exdeps_canRunBuildTwice() {

        // running `swift build` multiple times should not fail
        // subsequent executions to an unmodified source tree
        // should immediately exit with exit-status: `0`

        fixture(name: "102_mattts_dealer") { prefix in
            let prefix = Path.join(prefix, "app")
            try executeSwiftBuild(prefix)
            try executeSwiftBuild(prefix)
            try executeSwiftBuild(prefix)
        }
    }


    func test_get_ExternalDeps() {
        fixture(name: "100_external_deps") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/Bar"))
            XCTAssertTrue(Path.join(prefix, "Bar/Packages/Foo-1.2.3").isDirectory)
            XCTAssertTrue(Path.join(prefix, "Bar/.build/debug/Bar").isFile)
        }
    }

    func test_get_DealerBuild() {
        fixture(name: "101_mattts_dealer") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
        }
    }

    func test_get_DealerBuildOutput() {
        fixture(name: "102_mattts_dealer") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
            let output = try POSIX.popen(["\(prefix)/app/.build/debug/Dealer"])
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }

    func testNoArgumentsExitsWithOne() {
        var foo = false
        do {
            try executeSwiftBuild("/")
        } catch POSIX.Error.ExitStatus(let code, _) {

            // if our code crashes we'll get an exit code of 256
            XCTAssertEqual(code, Int32(1))

            foo = true
        } catch {
            XCTFail()
        }
        XCTAssertTrue(foo)
    }

    func testCompileFailureExitsGracefully() {
        fixture(name: "25_compile_fails") { prefix in
            var foo = false
            do {
                try executeSwiftBuild(prefix)
            } catch POSIX.Error.ExitStatus(let code, _) {

                // if our code crashes we'll get an exit code of 256
                XCTAssertEqual(code, Int32(1))

                foo = true
            } catch {
                XCTFail()
            }

            XCTAssertTrue(foo)
        }
    }

    func testDependenciesWithVPrefixTagsWork() {
        fixture(name: "102_mattts_dealer", tag: "v1.2.3") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
        }
    }

    func testWhenThereAreHyphensInThePath() {
        fixture(name: "103-mattts-dealer") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
        }
    }

    // 2: Package with one library target
    func testSingleTargetWithCustomName() {
        fixture(name: "25_single_target_with_custom_name") { prefix in
            XCTAssertNotNil(try? executeSwiftBuild(prefix))
            XCTAssertTrue(self.verifyFilesExist(["foo.a"], fixturePath: prefix))
        }
    }

    func testCanBuildIfADependencyAlreadyCheckedOut() {
        fixture(name: "102_mattts_dealer", tag: "v1.2.3") { prefix in
            try system("git", "clone", Path.join(prefix, "DeckOfPlayingCards"), Path.join(prefix, "app/Packages/DeckOfPlayingCards-1.2.3"))
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
        }
    }

    func testCanBuildIfADependencyClonedButThenAborted() {
        fixture(name: "102_mattts_dealer", tag: "v1.2.3") { prefix in
            try system("git", "clone", Path.join(prefix, "DeckOfPlayingCards"), Path.join(prefix, "app/Packages/DeckOfPlayingCards"))
            XCTAssertNotNil(try? executeSwiftBuild("\(prefix)/app"))
        }
    }
}
