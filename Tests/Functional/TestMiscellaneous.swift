import XCTest
import XCTestCaseProvider
import func libc.fclose
import func libc.sleep
import enum POSIX.Error
import func POSIX.fopen
import func POSIX.fputs
import func POSIX.popen
import struct sys.Path

class MiscellaneousTestCase: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () throws -> Void)] {
        return [
            ("testPrintsSelectedDependencyVersion", testPrintsSelectedDependencyVersion),
            ("testManifestExcludes1", testManifestExcludes1),
            ("testManifestExcludes2", testManifestExcludes2),
            ("testTestDependenciesSimple", testTestDependenciesSimple),
            ("testTestDependenciesComplex", testTestDependenciesComplex),
            ("testPassExactDependenciesToBuildCommand", testPassExactDependenciesToBuildCommand),
            ("testCanBuildMoreThanTwiceWithExternalDependencies", testCanBuildMoreThanTwiceWithExternalDependencies),
            ("testNoArgumentsExitsWithOne", testNoArgumentsExitsWithOne),
            ("testCompileFailureExitsGracefully", testCompileFailureExitsGracefully),
            ("testDependenciesWithVPrefixTagsWork", testDependenciesWithVPrefixTagsWork),
            ("testCanBuildIfADependencyAlreadyCheckedOut", testCanBuildIfADependencyAlreadyCheckedOut),
            ("testCanBuildIfADependencyClonedButThenAborted", testCanBuildIfADependencyClonedButThenAborted),
            ("testTipHasNoPackageSwift", testTipHasNoPackageSwift),
            ("testFailsIfVersionTagHasNoPackageSwift", testFailsIfVersionTagHasNoPackageSwift),
            ("testPackageManagerDefine", testPackageManagerDefine),
            ("testInternalDependencyEdges", testInternalDependencyEdges),
            ("testExternalDependencyEdges1", testExternalDependencyEdges1),
            ("testExternalDependencyEdges2", testExternalDependencyEdges2),
        ]
    }

    func testPrintsSelectedDependencyVersion() {

        // verifies the stdout contains information about 
        // the selected version of the package

        fixture(name: "DependencyResolution/External/Simple", tags: ["1.3.5"]) { prefix in
            let output = try executeSwiftBuild("\(prefix)/Bar")
            let lines = output.characters.split("\n").map(String.init)
            XCTAssertTrue(lines.contains("Using version 1.3.5 of package Foo"))
        }
    }

    func testManifestExcludes1() {

        // Tests exclude syntax where no target customization is specified

        fixture(name: "Miscellaneous/ExcludeDiagnostic1") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "BarLib.a")
            XCTAssertFileExists(prefix, ".build", "debug", "FooBarLib.a")
            XCTAssertNoSuchPath(prefix, ".build", "debug", "FooLib.a")
        }
    }

    func testManifestExcludes2() {

        // Tests exclude syntax where target customization is also specified
        // Refs: https://github.com/apple/swift-package-manager/pull/83

        fixture(name: "Miscellaneous/ExcludeDiagnostic2") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "BarLib.a")
            XCTAssertFileExists(prefix, ".build", "debug", "FooBarLib.a")
            XCTAssertNoSuchPath(prefix, ".build", "debug", "FooLib.a")
        }
    }

    func testTestDependenciesSimple() {
        fixture(name: "TestDependencies/Simple") { prefix in
            XCTAssertBuilds(prefix, "App")
            XCTAssertDirectoryExists(prefix, "App/Packages/TestingLib-1.2.3")
            XCTAssertFileExists(prefix, "App/.build/debug/Foo.a")
            XCTAssertFileExists(prefix, "App/.build/debug/TestingLib.a")
        }
    }

    func testTestDependenciesComplex() {

        // verifies that testDependencies of dependencies are not fetched or built

        fixture(name: "TestDependencies/Complex") { prefix in
            XCTAssertBuilds(prefix, "App")

            XCTAssertDirectoryExists(prefix, "App/Packages/TestingLib-1.2.3")
            XCTAssertDirectoryExists(prefix, "App/Packages/Foo-1.2.3")

            XCTAssertFileExists(prefix, "App/.build/debug/App")
            XCTAssertFileExists(prefix, "App/.build/debug/Foo.a")
            XCTAssertFileExists(prefix, "App/.build/debug/TestingLib.a")

            XCTAssertNoSuchPath(prefix, "App/Packages/PrivateFooLib-1.2.3")
            XCTAssertNoSuchPath(prefix, "App/Packages/TestingFooLib-1.2.3")
            XCTAssertNoSuchPath(prefix, "App/.build/debug/PrivateFooLib.a")
            XCTAssertNoSuchPath(prefix, "App/.build/debug/TestingFooLib.a")
        }
    }

    func testPassExactDependenciesToBuildCommand() {

        // regression test to ensure that dependencies of other dependencies
        // are not passed into the build-command.

        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuilds(prefix, "app")
            XCTAssertFileExists(prefix, "app/.build/debug/FooExec")
            XCTAssertFileExists(prefix, "app/.build/debug/FooLib1.a")
            XCTAssertFileExists(prefix, "app/.build/debug/FooLib2.a")
        }
    }

    func testCanBuildMoreThanTwiceWithExternalDependencies() {

        // running `swift build` multiple times should not fail
        // subsequent executions to an unmodified source tree
        // should immediately exit with exit-status: `0`

        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix, "app")
            XCTAssertBuilds(prefix, "app")
            XCTAssertBuilds(prefix, "app")
        }
    }

    func testDependenciesWithVPrefixTagsWork() {
        fixture(name: "DependencyResolution/External/Complex", tags: ["v1.2.3"]) { prefix in
            XCTAssertBuilds(prefix, "app")
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
        fixture(name: "Miscellaneous/CompileFails") { prefix in
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

    func testCanBuildIfADependencyAlreadyCheckedOut() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            try system("git", "clone", Path.join(prefix, "deck-of-playing-cards"), Path.join(prefix, "app/Packages/DeckOfPlayingCards-1.2.3"))
            XCTAssertBuilds(prefix, "app")
        }
    }

    func testCanBuildIfADependencyClonedButThenAborted() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            try system("git", "clone", Path.join(prefix, "deck-of-playing-cards"), Path.join(prefix, "app/Packages/DeckOfPlayingCards"))
            XCTAssertBuilds(prefix, "app")
        }
    }

    // if HEAD of the default branch has no Package.swift it is still
    // valid provided the selected version tag has a Package.swift
    func testTipHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = Path.join(prefix, "FisherYates")

            // required for some Linux configurations
            try system("git", "-C", path, "config", "user.email", "example@example.com")
            try system("git", "-C", path, "config", "user.name", "Example Example")

            try system("git", "-C", path, "rm", "Package.swift")
            try system("git", "-C", path, "commit", "-mwip")

            XCTAssertBuilds(prefix, "app")
        }
    }

    // if a tag does not have a valid Package.swift, the build fails
    func testFailsIfVersionTagHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = Path.join(prefix, "FisherYates")

            try system("git", "-C", path, "config", "user.email", "example@example.com")
            try system("git", "-C", path, "config", "user.name", "Example McExample")
            try system("git", "-C", path, "rm", "Package.swift")
            try system("git", "-C", path, "commit", "--message", "wip")
            try system("git", "-C", path, "tag", "--force", "1.2.3")

            XCTAssertBuildFails(prefix, "app")
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
            let execpath = [Path.join(prefix, ".build/debug/Foo")]

            XCTAssertBuilds(prefix)
            var output = try popen(execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            let fp = try fopen(prefix, "Bar/Bar.swift", mode: .Write)
            try POSIX.fputs("public let bar = \"Goodbye\"\n", fp)
            fclose(fp)

            XCTAssertBuilds(prefix)
            output = try popen(execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables that link to that module in the root package.
    */
    func testExternalDependencyEdges1() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let execpath = [Path.join(prefix, "app/.build/debug/Dealer")]

            XCTAssertBuilds(prefix, "app")
            var output = try popen(execpath)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            let fp = try fopen(prefix, "app/Packages/FisherYates-1.2.3/src/Fisher-Yates_Shuffle.swift", mode: .Write)
            try POSIX.fputs("public extension CollectionType{ func shuffle() -> [Generator.Element] {return []} }\n\npublic extension MutableCollectionType where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerate() { self[i] = self[0] } }}\n\npublic let shuffle = true", fp)
            fclose(fp)

            XCTAssertBuilds(prefix, "app")
            output = try popen(execpath)
            XCTAssertEqual(output, "♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n♠︎A\n")
        }
    }

    /**
     Tests that modules from other packages that are rebuilt causes
     any executables for another external package to be rebuilt.
     */
    func testExternalDependencyEdges2() {
        fixture(name: "Miscellaneous/DependencyEdges/External") { prefix in
            let execpath = [Path.join(prefix, "root/.build/debug/dep2")]

            XCTAssertBuilds(prefix, "root")
            var output = try popen(execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            let fp = try fopen(prefix, "root/Packages/dep1-1.2.3/Foo.swift", mode: .Write)
            try POSIX.fputs("public let foo = \"Goodbye\"", fp)
            fclose(fp)

            XCTAssertBuilds(prefix, "root")
            output = try popen(execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }
}
