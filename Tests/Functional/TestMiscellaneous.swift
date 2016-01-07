import XCTest
import XCTestCaseProvider
import enum POSIX.Error
import func POSIX.popen
import struct sys.Path

class MiscellaneousTestCase: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> Void)] {
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
        ]
    }

    func testPrintsSelectedDependencyVersion() {

        // verifies the stdout contains information about 
        // the selected version of the package

        fixture(name: "DependencyResolution/External/Simple", tag: "1.3.5") { prefix in
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
        fixture(name: "DependencyResolution/External/Complex", tag: "v1.2.3") { prefix in
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
}
