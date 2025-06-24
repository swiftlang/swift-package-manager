/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import _IntegrationTestSupport
import _InternalTestSupport
import Testing

@Suite
private struct XCBuildTests {
    @Test(.requireHostOS(.macOS))
    func testExecutableProducts() async throws {
        try await fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(fooPath, buildSystem: .xcode)
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try await executeSwiftBuild(fooPath, configuration: .release, buildSystem: .xcode)
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        try await fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--product",
                    "foo",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--product",
                    "foo",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        try await fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--product",
                    "cfoo",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--product",
                    "cfoo",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        try await fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--product",
                    "bar",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cbar")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--product",
                    "bar",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "foo")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cfoo")))
            #expect(localFileSystem.exists(releasePath.appending(component: "bar")))
            #expect(localFileSystem.notExists(releasePath.appending(component: "cbar")))
        }

        try await fixture(name: "XCBuild/ExecutableProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--product",
                    "cbar",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "foo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "cfoo")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "bar")))
            #expect(localFileSystem.exists(debugPath.appending(component: "cbar")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--product",
                    "cbar",
                ],
                buildSystem: .xcode,
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
    func testTestProducts() async throws {
        try await fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        try await fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--build-tests",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--build-tests",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        try await fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "FooTests",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "FooTests",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }

        try await fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "CFooTests",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(debugPath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "CFooTests",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "FooTests.xctest")))
            #expect(localFileSystem.isDirectory(releasePath.appending(component: "CFooTests.xctest")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib.o")))
        }
    }

    @Test(.requireHostOS(.macOS))
    func testLibraryProductsAndTargets() async throws {
        try await fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        try await fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "FooLib",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "FooLib",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        try await fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "CFooLib",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "CFooLib",
                ],
                buildSystem: .xcode,
            )
            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.notExists(releasePath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(releasePath.appending(component: "BarLib_Module.o")))
        }

        try await fixture(name: "XCBuild/Libraries") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")

            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "BarLib",
                ],
                buildSystem: .xcode,
            )
            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.notExists(debugPath.appending(component: "FooLib_Module.o")))
            #expect(localFileSystem.notExists(debugPath.appending(component: "CFooLib_Module.o")))
            #expect(localFileSystem.exists(debugPath.appending(component: "BarLib_Module.o")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "BarLib",
                ],
                buildSystem: .xcode,
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
    func testSystemTargets() async throws {
        try await fixture(name: "XCBuild/SystemTargets") { path in
            let fooPath = path.appending(component: "Foo")
            let binaryPath = fooPath.appending(components: ".build", "apple", "Products")
            let inputsPath = path.appending(component: "Inputs")

            // Because there isn't any one system target that we can depend on for testing purposes, we build our own.
            let sourcePath = inputsPath.appending(component: "libsys.c")
            let libraryPath = inputsPath.appending(component: "libsys.a")
            try sh(clang, "-c", sourcePath, "-o", libraryPath)

            // let env = Environment(["PKG_CONFIG_PATH": inputsPath.pathString])
            var env = Environment()
            env["PKG_CONFIG_PATH"] = inputsPath.pathString
            try await executeSwiftBuild(
                fooPath,
                extraArgs: [
                    "--target",
                    "foo",
                ],
                env: env,
                buildSystem: .xcode,
            )

            let debugPath = binaryPath.appending(component: "Debug")
            #expect(localFileSystem.exists(debugPath.appending(component: "foo")))

            try await executeSwiftBuild(
                fooPath,
                configuration: .release,
                extraArgs: [
                    "--target",
                    "foo",
                ],
                env: env,
                buildSystem: .xcode,
            )

            let releasePath = binaryPath.appending(component: "Release")
            #expect(localFileSystem.exists(releasePath.appending(component: "foo")))
        }
    }

    @Test(.skip("FIXME: This test randomly succeeds or fails, depending on the order the subtasks are executed in."))
    func testBinaryTargets() async throws {
        try await binaryTargetsFixture { path in
            try await executeSwiftBuild(
                path,
                configuration: .debug,
                extraArgs: ["--target", "exe"],
                buildSystem: .xcode,
            )
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .skipIfXcodeBuilt(),
        .skip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")
    )
    func testSwiftTest() async throws {
        try await fixture(name: "XCBuild/TestProducts") { path in
            let fooPath = path.appending(component: "Foo")

            do {
                let output = try await executeSwiftTest(fooPath, buildSystem: .xcode)
                #expect(output.stderr.contains("Test Suite 'FooTests.xctest'"))
                #expect(output.stderr.contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let output = try await executeSwiftTest(
                    fooPath,
                    extraArgs: [
                        "--filter",
                        "CFooTests",
                    ],
                    buildSystem: .xcode,
                )
                #expect(output.stderr.contains("Test Suite 'Selected tests' started"))
                #expect(output.stderr.contains("Test Suite 'CFooTests.xctest'"))
            }

            do {
                let output = try await executeSwiftTest(
                    fooPath, 
                    extraArgs: ["--parallel"],
                    buildSystem: .xcode, 
                )
                #expect(output.stdout.contains("Testing FooTests"))
                #expect(output.stdout.contains("Testing CFooTests"))
            }
        }
    }
}
