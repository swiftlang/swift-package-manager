/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel

import struct Utility.Path
import class Utility.Git
import func libc.sleep
import enum POSIX.Error
import func POSIX.popen

class MiscellaneousTestCase: XCTestCase {
    func testPrintsSelectedDependencyVersion() {

        // verifies the stdout contains information about 
        // the selected version of the package

        fixture(name: "DependencyResolution/External/Simple", tags: ["1.3.5"]) { prefix in
            let output = try executeSwiftBuild(prefix.appending("Bar"))
            let lines = output.characters.split(separator: "\n").map(String.init)
            XCTAssertTrue(lines.contains("Resolved version: 1.3.5"))
        }
    }

    func testPackageWithNoSources() throws {
        // Tests that a package with no source files doesn't error.
        fixture(name: "Miscellaneous/Empty") { prefix in
            let output = try executeSwiftBuild(prefix, configuration: .Debug)
            XCTAssert(output.contains("warning: root package 'Empty' does not contain any sources"), "unexpected output: \(output)")
        }
    }

    func testPackageWithNoSourcesButDependency() throws {
        // Tests a package with no source files but a dependency builds.
        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            let output = try executeSwiftBuild(prefix.appending("EmptyWithDependency"))
            XCTAssert(output.contains("warning: root package 'EmptyWithDependency' does not contain any sources"), "unexpected output: \(output)")
            XCTAssertFileExists(prefix.appending("EmptyWithDependency/.build/debug/FooLib2.swiftmodule"))
        }
    }

    func testPackageWithEmptyDependency() throws {
        // Tests a package with an empty dependency fails (we only allow it in the root package).
        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuildFails(prefix.appending("HasEmptyDependency"))
        }
    }

    func testManifestExcludes1() {

        // Tests exclude syntax where no target customization is specified

        fixture(name: "Miscellaneous/ExcludeDiagnostic1") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("BarLib.swiftmodule"))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("FooBarLib.swiftmodule"))
            XCTAssertNoSuchPath(prefix.appending(".build").appending("debug").appending("FooLib.swiftmodule"))
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
            XCTAssertBuilds(prefix.appending("App"))
            XCTAssertFileExists(prefix.appending("App").appending(".build").appending("debug").appending("App"))
            XCTAssertFileExists(prefix.appending("App").appending(".build").appending("debug").appending("top"))
            XCTAssertFileExists(prefix.appending("App").appending(".build").appending("debug").appending("bottom.swiftmodule"))
            XCTAssertNoSuchPath(prefix.appending("App").appending(".build").appending("debug").appending("some"))
        }
    }
    
    func testManifestExcludes4() {
        
        // exclude directory is inside Tests folder (Won't build without exclude)
        
        fixture(name: "Miscellaneous/ExcludeDiagnostic4") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("FooPackage.swiftmodule"))
        }
    }
    
    func testManifestExcludes5() {
        
        // exclude directory is Tests folder (Won't build without exclude)
        
        fixture(name: "Miscellaneous/ExcludeDiagnostic5") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("FooPackage.swiftmodule"))
        }
    }

    func testTestDependenciesSimple() {
    #if false
        //FIXME disabled pending no more magic
        fixture(name: "TestDependencies/Simple") { prefix in
            XCTAssertBuilds(prefix.appending("App"))
            XCTAssertDirectoryExists(prefix.appending("App/Packages/TestingLib-1.2.3"))
            XCTAssertFileExists(prefix.appending("App/.build/debug/Foo.swiftmodule"))
            XCTAssertFileExists(prefix.appending("App/.build/debug/TestingLib.swiftmodule"))
        }
    #endif
    }

    func testTestDependenciesComplex() {
    #if false
        //FIXME disabled pending no more magic

        // verifies that testDependencies of dependencies are not fetched or built

        fixture(name: "TestDependencies/Complex") { prefix in
            XCTAssertBuilds(prefix.appending("App"))

            XCTAssertDirectoryExists(prefix.appending("App/Packages/TestingLib-1.2.3"))
            XCTAssertDirectoryExists(prefix.appending("App/Packages/Foo-1.2.3"))

            XCTAssertFileExists(prefix.appending("App/.build/debug/App"))
            XCTAssertFileExists(prefix.appending("App/.build/debug/Foo.swiftmodule"))
            XCTAssertFileExists(prefix.appending("App/.build/debug/TestingLib.swiftmodule"))

            XCTAssertNoSuchPath(prefix.appending("App/Packages/PrivateFooLib-1.2.3"))
            XCTAssertNoSuchPath(prefix.appending("App/Packages/TestingFooLib-1.2.3"))
            XCTAssertNoSuchPath(prefix.appending("App/.build/debug/PrivateFooLib.swiftmodule"))
            XCTAssertNoSuchPath(prefix.appending("App/.build/debug/TestingFooLib.swiftmodule"))
        }
#endif
    }


    func testPassExactDependenciesToBuildCommand() {

        // regression test to ensure that dependencies of other dependencies
        // are not passed into the build-command.

        fixture(name: "Miscellaneous/ExactDependencies") { prefix in
            XCTAssertBuilds(prefix.appending("app"))
            XCTAssertFileExists(prefix.appending("app/.build/debug/FooExec"))
            XCTAssertFileExists(prefix.appending("app/.build/debug/FooLib1.swiftmodule"))
            XCTAssertFileExists(prefix.appending("app/.build/debug/FooLib2.swiftmodule"))
        }
    }

    func testCanBuildMoreThanTwiceWithExternalDependencies() {

        // running `swift build` multiple times should not fail
        // subsequent executions to an unmodified source tree
        // should immediately exit with exit-status: `0`

        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix.appending("app"))
            XCTAssertBuilds(prefix.appending("app"))
            XCTAssertBuilds(prefix.appending("app"))
        }
    }

    func testDependenciesWithVPrefixTagsWork() {
        fixture(name: "DependencyResolution/External/Complex", tags: ["v1.2.3"]) { prefix in
            XCTAssertBuilds(prefix.appending("app"))
        }
    }

    func testNoArgumentsExitsWithOne() {
        var foo = false
        do {
            try executeSwiftBuild("/")
        } catch POSIX.Error.exitStatus(let code, _) {

            // if our code crashes we'll get an exit code of 256
            XCTAssertEqual(code, Int32(1))

            foo = true
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
            } catch POSIX.Error.exitStatus(let code, _) {

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
            try systemQuietly(Git.tool, "clone", prefix.appending("deck-of-playing-cards").asString, prefix.appending("app/Packages/DeckOfPlayingCards-1.2.3").asString)
            XCTAssertBuilds(prefix.appending("app"))
        }
    }

    func testCanBuildIfADependencyClonedButThenAborted() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            try systemQuietly(Git.tool, "clone", prefix.appending("deck-of-playing-cards").asString, prefix.appending("app/Packages/DeckOfPlayingCards").asString)
            XCTAssertBuilds(prefix.appending("app"), configurations: [.Debug])
        }
    }

    // if HEAD of the default branch has no Package.swift it is still
    // valid provided the selected version tag has a Package.swift
    func testTipHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = prefix.appending("FisherYates")

            // required for some Linux configurations
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.email", "example@example.com")
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.name", "Example Example")

            try systemQuietly(Git.tool, "-C", path.asString, "rm", "Package.swift")
            try systemQuietly(Git.tool, "-C", path.asString, "commit", "-mwip")

            XCTAssertBuilds(prefix.appending("app"))
        }
    }

    // if a tag does not have a valid Package.swift, the build fails
    func testFailsIfVersionTagHasNoPackageSwift() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let path = prefix.appending("FisherYates")

            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.email", "example@example.com")
            try systemQuietly(Git.tool, "-C", path.asString, "config", "user.name", "Example McExample")
            try systemQuietly(Git.tool, "-C", path.asString, "rm", "Package.swift")
            try systemQuietly(Git.tool, "-C", path.asString, "commit", "--message", "wip")
            try systemQuietly(Git.tool, "-C", path.asString, "tag", "--force", "1.2.3")

            XCTAssertBuildFails(prefix.appending("app"))
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
            let execpath = [prefix.appending(".build/debug/Foo").asString]

            XCTAssertBuilds(prefix)
            var output = try popen(execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            try localFileSystem.writeFileContents(prefix.appending("Bar/Bar.swift"), bytes: "public let bar = \"Goodbye\"\n")

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
            let execpath = [prefix.appending("app/.build/debug/Dealer").asString]

            XCTAssertBuilds(prefix.appending("app"))
            var output = try popen(execpath)
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            try localFileSystem.writeFileContents(prefix.appending("app/Packages/FisherYates-1.2.3/src/Fisher-Yates_Shuffle.swift"), bytes: "public extension Collection{ func shuffle() -> [Iterator.Element] {return []} }\n\npublic extension MutableCollection where Index == Int { mutating func shuffleInPlace() { for (i, _) in enumerated() { self[i] = self[0] } }}\n\npublic let shuffle = true")

            XCTAssertBuilds(prefix.appending("app"))
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
            let execpath = [prefix.appending("root/.build/debug/dep2").asString]

            XCTAssertBuilds(prefix.appending("root"))
            var output = try popen(execpath)
            XCTAssertEqual(output, "Hello\n")

            // we need to sleep at least one second otherwise
            // llbuild does not realize the file has changed
            sleep(1)

            try localFileSystem.writeFileContents(prefix.appending("root/Packages/dep1-1.2.3/Foo.swift"), bytes: "public let foo = \"Goodbye\"")

            XCTAssertBuilds(prefix.appending("root"))
            output = try popen(execpath)
            XCTAssertEqual(output, "Goodbye\n")
        }
    }

    func testProducts() {
        fixture(name: "Products/StaticLibrary") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build/debug/libProductName.a"))
        }
        fixture(name: "Products/DynamicLibrary") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", "debug", "libProductName.\(Product.dynamicLibraryExtension)"))
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
            XCTAssertFileExists(prefix.appending(".build/debug/Module_Name_1.build/Foo.swift.o"))
        }
    }

    func testInitPackageNonc99Directory() throws {
        let tempDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        XCTAssertTrue(localFileSystem.isDirectory(tempDir.path))

        // Create a directory with non c99name.
        let packageRoot = tempDir.path.appending("some-package")
        try localFileSystem.createDirectory(packageRoot)
        XCTAssertTrue(localFileSystem.isDirectory(packageRoot))

        // Run package init.
        _ = try SwiftPMProduct.SwiftPackage.execute(["init"], chdir: packageRoot, env: [:], printIfError: true)
        // Try building it.
        XCTAssertBuilds(packageRoot)
        XCTAssertFileExists(packageRoot.appending(".build/debug/some_package.swiftmodule"))
    }

    static var allTests = [
        ("testPrintsSelectedDependencyVersion", testPrintsSelectedDependencyVersion),
        ("testPackageWithNoSources", testPackageWithNoSources),
        ("testPackageWithNoSourcesButDependency", testPackageWithNoSourcesButDependency),
        ("testPackageWithEmptyDependency", testPackageWithEmptyDependency),
        ("testManifestExcludes1", testManifestExcludes1),
        ("testManifestExcludes2", testManifestExcludes2),
        ("testManifestExcludes3", testManifestExcludes3),
        ("testManifestExcludes4", testManifestExcludes4),
        ("testManifestExcludes5", testManifestExcludes5),
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
        ("testProducts", testProducts),
        ("testProductWithNoModules", testProductWithNoModules),
        ("testProductWithMissingModules", testProductWithMissingModules),
        ("testSpaces", testSpaces),
        ("testInitPackageNonc99Directory", testInitPackageNonc99Directory),
    ]
}
