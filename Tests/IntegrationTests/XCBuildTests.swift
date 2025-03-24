/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCTestSupport
import IntegrationTestSupport
import Testing

@Suite
private struct XCBuildTests {
    @Test(.requireHostOS(.macOS))
    func testExecutableProducts() throws {
        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "foo")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--product",
                "foo",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cfoo")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--product",
                "cfoo",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "bar")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--product",
                "bar",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--product", "cbar")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cbar")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--product",
                "cbar",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cbar")))
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .skip(
            "FIXME: /.../XCBuild_TestProducts.551ajO/Foo/.build/apple/Intermediates.noindex/GeneratedModuleMaps/macosx/FooLib.modulemap:2:12: error: header 'FooLib-Swift.h' not found"
        )
    )
    func testTestProducts() throws {
        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--build-tests")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--build-tests", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooTests")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "FooTests",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooTests")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "CFooTests",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }
    }

    @Test(.requireHostOS(.macOS))
    func testLibraryProductsAndTargets() throws {
        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "-c", "release")
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "FooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "FooLib",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "CFooLib")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "CFooLib",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try sh(swiftBuild, "--package-path", fooPath, "--build-system", "xcode", "--target", "BarLib")
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "BarLib",
                "-c",
                "release"
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .skip(
            "FIXME: ld: warning: ignoring file /../XCBuild_SystemTargets.b38QoO/Inputs/libsys.a, building for macOS-arm64 but attempting to link with file built for unknown-x86_64\n\nUndefined symbols for architecture arm64:\n  \"_GetSystemLibName\", referenced from:\n      _main in main.o\n\nld: symbol(s) not found for architecture arm64\n\nclang: error: linker command failed with exit code 1 (use -v to see invocation)\n\nBuild cancelled\n"
        )
    )
    func testSystemTargets() throws {
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
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))

            try sh(
                swiftBuild,
                "--package-path",
                fooPath,
                "--build-system",
                "xcode",
                "--target",
                "foo",
                "-c",
                "release",
                env: env
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
        }
    }

    @Test(.skip("FIXME: This test randomly succeeds or fails, depending on the order the subtasks are executed in."))
    func testBinaryTargets() throws {
        try binaryTargetsFixture { path in
            try sh(swiftBuild, "--package-path", path, "-c", "debug", "--build-system", "xcode", "--target", "exe")
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .skipIfXcodeBuilt(),
        .skip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")
    )
    func testSwiftTest() throws {
        fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")

            do {
                let (_, stderr) = try sh(swiftTest, "--package-path", fooPath, "--build-system", "xcode")
                #expect(stderr.contains("Test Suite 'FooTests.xctest'"))
                #expect(stderr.contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let (_, stderr) = try sh(
                    swiftTest,
                    "--package-path",
                    fooPath,
                    "--build-system",
                    "xcode",
                    "--filter",
                    "CFooTests"
                )
                #expect(stderr.contains("Test Suite 'Selected tests' started"))
                #expect(stderr.contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let (stdout, _) = try sh(swiftTest, "--package-path", fooPath, "--build-system", "xcode", "--parallel")
                #expect(stdout.contains("Testing FooTests"))
                #expect(stdout.contains("Testing CFooTests"))
            }
        }
    }
}
