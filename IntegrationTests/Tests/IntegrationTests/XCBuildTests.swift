/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCUtility
import TSCTestSupport

final class XCBuildTests: XCTestCase {
  #if os(macOS)
    func testExecutableProducts() throws {
        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "foo"))
            XCTAssertFileExists(debugPath.appending(component: "cfoo"))
            XCTAssertFileExists(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "foo"))
            XCTAssertFileExists(releasePath.appending(component: "cfoo"))
            XCTAssertFileExists(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "foo"))
            XCTAssertFileExists(debugPath.appending(component: "cfoo"))
            XCTAssertFileExists(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "foo"))
            XCTAssertFileExists(releasePath.appending(component: "cfoo"))
            XCTAssertFileExists(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "cfoo")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertFileExists(debugPath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "cfoo", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertFileExists(releasePath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "bar")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cfoo"))
            XCTAssertFileExists(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "bar", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cfoo"))
            XCTAssertFileExists(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "cbar")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "bar"))
            XCTAssertFileExists(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "cbar", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "bar"))
            XCTAssertFileExists(releasePath.appending(component: "cbar"))
        }
    }

    func testTestProducts() throws {
        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(debugPath.appending(component: "FooTests.xctest"))
            XCTAssertNoSuchPath(debugPath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(releasePath.appending(component: "FooTests.xctest"))
            XCTAssertNoSuchPath(releasePath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--build-tests")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertDirectoryExists(debugPath.appending(component: "FooTests.xctest"))
            XCTAssertDirectoryExists(debugPath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--build-tests", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertDirectoryExists(releasePath.appending(component: "FooTests.xctest"))
            XCTAssertDirectoryExists(releasePath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooTests")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertDirectoryExists(debugPath.appending(component: "FooTests.xctest"))
            XCTAssertNoSuchPath(debugPath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooTests", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertDirectoryExists(releasePath.appending(component: "FooTests.xctest"))
            XCTAssertNoSuchPath(releasePath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooTests")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(debugPath.appending(component: "FooTests.xctest"))
            XCTAssertDirectoryExists(debugPath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooTests", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(releasePath.appending(component: "FooTests.xctest"))
            XCTAssertDirectoryExists(releasePath.appending(component: "CFooTests.xctest"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }
    }

    func testLibraryProductsAndTargets() throws {
        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "FooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "FooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "BarLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(debugPath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "BarLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "FooLib.o"))
            XCTAssertNoSuchPath(releasePath.appending(component: "CFooLib.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib.o"))
        }
    }

    func testSystemTargets() throws {
        fixture(name: "XCBuild/SystemTargets") { path in
            let fooPath = path.appending(component: "Foo")
            let env = ["PKG_CONFIG_PATH": path.appending(component: "Inputs").pathString]
            let binaryPath = fooPath.appending(components: ".build", "x86_64-apple-macosx", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo", env: env)
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "foo"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo", "-c", "release", env: env)
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "foo"))
        }
    }

    //FIXME: This test randomly succeeds or fails, depending on the order the subtasks are executed in.
    func _testBinaryTargets() throws {
        fixture(name: "XCBuild/BinaryTargets") { path in
            try sh(swiftBuild, "--package-path", path, "-c", "debug", "--build-system", "xcode", "--target", "exe")
        }
    }
  #endif
}
