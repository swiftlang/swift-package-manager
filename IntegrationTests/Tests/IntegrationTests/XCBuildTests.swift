/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TSCBasic
import TSCTestSupport

final class XCBuildTests: XCTestCase {
    func testExecutableProducts() throws {
        #if !os(macOS)
        try XCTSkip("Test requires macOS")
        #endif

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

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
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "foo")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "foo"))
            XCTAssertFileExists(debugPath.appending(component: "cfoo"))
            XCTAssertFileExists(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "foo", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "foo"))
            XCTAssertFileExists(releasePath.appending(component: "cfoo"))
            XCTAssertFileExists(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cfoo")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertFileExists(debugPath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cfoo", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertFileExists(releasePath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "bar")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cfoo"))
            XCTAssertFileExists(debugPath.appending(component: "bar"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "bar", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cfoo"))
            XCTAssertFileExists(releasePath.appending(component: "bar"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cbar"))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cbar")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "foo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(debugPath.appending(component: "bar"))
            XCTAssertFileExists(debugPath.appending(component: "cbar"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cbar", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "foo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "cfoo"))
            XCTAssertNoSuchPath(releasePath.appending(component: "bar"))
            XCTAssertFileExists(releasePath.appending(component: "cbar"))
        }
    }

    func testTestProducts() throws {
        try XCTSkip("FIXME: /.../XCBuild_TestProducts.551ajO/Foo/.build/apple/Intermediates.noindex/GeneratedModuleMaps/macosx/FooLib.modulemap:2:12: error: header 'FooLib-Swift.h' not found")

        #if !os(macOS)
        try XCTSkip("Test requires macOS")
        #endif

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

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
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

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
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

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
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

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
        #if !os(macOS)
        try XCTSkip("Test requires macOS")
        #endif

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib_Module.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib_Module.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib_Module.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib_Module.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib_Module.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "FooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib_Module.o"))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "BarLib")
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertNoSuchPath(debugPath.appending(component: "FooLib_Module.o"))
            XCTAssertNoSuchPath(debugPath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(debugPath.appending(component: "BarLib_Module.o"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "BarLib", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertNoSuchPath(releasePath.appending(component: "FooLib_Module.o"))
            XCTAssertNoSuchPath(releasePath.appending(component: "CFooLib_Module.o"))
            XCTAssertFileExists(releasePath.appending(component: "BarLib_Module.o"))
        }
    }

    func testSystemTargets() throws {
        try XCTSkip("FIXME: ld: warning: ignoring file /../XCBuild_SystemTargets.b38QoO/Inputs/libsys.a, building for macOS-arm64 but attempting to link with file built for unknown-x86_64\n\nUndefined symbols for architecture arm64:\n  \"_GetSystemLibName\", referenced from:\n      _main in main.o\n\nld: symbol(s) not found for architecture arm64\n\nclang: error: linker command failed with exit code 1 (use -v to see invocation)\n\nBuild cancelled\n")

        #if !os(macOS)
        try XCTSkip("Test requires macOS")
        #endif

        fixture(name: "XCBuild/SystemTargets") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")
            let inputsPath = path.appending(component: "Inputs")

            // Because there isn't any one system target that we can depend on for testing purposes, we build our own.
            let sourcePath = inputsPath.appending(component: "libsys.c")
            let libraryPath = inputsPath.appending(component: "libsys.a")
            try sh(clang, "-c", sourcePath, "-o", libraryPath)

            let env = ["PKG_CONFIG_PATH": inputsPath.pathString]
            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo", env: env)
            let debugPath = binaryPath.appending(component: "Debug")
            XCTAssertFileExists(debugPath.appending(component: "foo"))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "foo", "-c", "release", env: env)
            let releasePath = binaryPath.appending(component: "Release")
            XCTAssertFileExists(releasePath.appending(component: "foo"))
        }
    }

    func testBinaryTargets() throws {
        try XCTSkip("FIXME: This test randomly succeeds or fails, depending on the order the subtasks are executed in.")

        try binaryTargetsFixture { path in
            try sh(swiftBuild, "--package-path", path, "-c", "debug", "--build-system", "xcode", "--target", "exe")
        }
    }

    func testSwiftTest() throws {
        try XCTSkip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")

        #if !os(macOS) || Xcode
        try XCTSkip("Test requires macOS")
        #endif

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")

            do {
                let (_, stderr) = try sh(swiftTest, "--package-path", fooPath, "--build-system", "xcode")
                XCTAssertMatch(stderr, .contains("Test Suite 'FooTests.xctest'"))
                XCTAssertMatch(stderr, .contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let (_, stderr) = try sh(swiftTest, "--package-path", fooPath, "--build-system", "xcode", "--filter", "CFooTests")
                XCTAssertMatch(stderr, .contains("Test Suite 'Selected tests' started"))
                XCTAssertMatch(stderr, .contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let (stdout, _) = try sh(swiftTest, "--package-path", fooPath, "--build-system", "xcode", "--parallel")
                XCTAssertMatch(stdout, .contains("Testing FooTests"))
                XCTAssertMatch(stdout, .contains("Testing CFooTests"))
            }
        }
    }
}
