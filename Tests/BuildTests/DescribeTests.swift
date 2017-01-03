/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
@testable import Build
import PackageDescription
import PackageGraph
import PackageModel
import Utility
import TestSupport

final class DescribeTests: XCTestCase {
    let dummyPackage = Package(manifest: Manifest(path: AbsolutePath("/"), url: "/", package: PackageDescription.Package(name: "Foo"), version: nil), path: AbsolutePath("/"), modules: [], testModules: [], products: [], dependencies: [])
    
    struct InvalidToolchain: Toolchain {
        var swiftCompiler: AbsolutePath { fatalError() }
        var clangCompiler: AbsolutePath { fatalError() }
        var defaultSDK: AbsolutePath?  { fatalError() }
        var swiftPlatformArgs: [String] { fatalError() }
        var clangPlatformArgs: [String] { fatalError() }
    }

    struct DummyToolchain: Toolchain {
        var swiftCompiler = AbsolutePath("/fake/path/to/swiftc")
        var clangCompiler = AbsolutePath("/fake/path/to/clang")
        var defaultSDK: AbsolutePath? = nil
        var swiftPlatformArgs: [String] = []
        var clangPlatformArgs: [String] = []
    }

    func testDescribingNoModulesThrows() {
        do {
            let tempDir = try TemporaryDirectory(removeTreeOnDeinit: true)
            let graph = PackageGraph(rootPackages: [dummyPackage], modules: [], externalModules: [])
            _ = try describe(tempDir.path.appending(component: "foo"), .debug, graph, flags: BuildFlags(), toolchain: InvalidToolchain())
            XCTFail("This call should throw")
        } catch Build.Error.noModules {
            XCTAssert(true, "This error should be thrown")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }

    func testDescribingCModuleThrows() {
        do {
            let tempDir = try TemporaryDirectory(removeTreeOnDeinit: true)
            let graph = PackageGraph(rootPackages: [dummyPackage], modules: [CModule(name: "MyCModule", sources: Sources(paths: [], root: AbsolutePath("/")), path: AbsolutePath("/"))], externalModules: [])
            _ = try describe(tempDir.path.appending(component: "foo"), .debug, graph, flags: BuildFlags(), toolchain: InvalidToolchain())
            XCTFail("This call should throw")
        } catch Build.Error.onlyCModule (let name) {
            XCTAssert(true, "This error should be thrown")
            XCTAssertEqual(name, "MyCModule")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }

    func testClangModuleCanHaveSwiftDep() throws {
        let swiftModule = SwiftModule(name: "SwiftModule", sources: Sources(paths: [], root: .root))
        let clangModule = ClangModule(name: "ClangModule", sources: Sources(paths: [], root: .root), dependencies: [swiftModule])
        let buildMeta = ClangModuleBuildMetadata(module: clangModule, prefix: .root, otherArgs: [])
        XCTAssertEqual(buildMeta.inputs, ["/SwiftModule.swiftmodule"])
    }

    func testCppLinkCommand() throws {
        mktmpdir { path in
            let fs = InMemoryFileSystem(emptyFiles:
                "/Pkg/Sources/swift/main.swift",
                "/Pkg/Sources/c/main.c",
                "/Pkg/Sources/cpp/main.cpp"
            )
            let graph = try loadMockPackageGraph(["/Pkg": Package(name: "Pkg")], root: "/Pkg", in: fs)
            let yaml = try describe(path.appending(component: "foo"), .debug, graph, flags: BuildFlags(), toolchain: DummyToolchain())
            // FIXME: This is not a good test but should be good enough until we have the Buld re-write.
            XCTAssertTrue(try localFileSystem.readFileContents(yaml).asString!.contains("-lc++"))
        }
    }

    static var allTests = [
        ("testDescribingNoModulesThrows", testDescribingNoModulesThrows),
        ("testDescribingCModuleThrows", testDescribingCModuleThrows),
        ("testClangModuleCanHaveSwiftDep", testClangModuleCanHaveSwiftDep),
        ("testCppLinkCommand", testCppLinkCommand),
    ]
}
