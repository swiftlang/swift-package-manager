/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility
import TestSupport
import PackageModel

@testable import Build
import PackageDescription
import PackageDescription4

private struct MockToolchain: Toolchain {
    let swiftCompiler = AbsolutePath("/fake/path/to/swiftc")
    let clangCompiler = AbsolutePath("/fake/path/to/clang")
    let extraCCFlags: [String] = []
    let extraSwiftCFlags: [String] = []
    #if os(macOS)
    let extraCPPFlags: [String] = ["-lc++"]
    #else
    let extraCPPFlags: [String] = ["-lstdc++"]
    #endif
  #if os(macOS)
    let dynamicLibraryExtension = "dylib"
  #else
    let dynamicLibraryExtension = "so"
  #endif
}

final class BuildPlanTests: XCTestCase {

    func mockBuildParameters(buildPath: AbsolutePath = AbsolutePath("/path/to/build"), config: Build.Configuration = .debug) -> BuildParameters {
        return BuildParameters(
            dataPath: buildPath,
            configuration: config,
            toolchain: MockToolchain(),
            flags: BuildFlags())
    }

    func testBasicSwiftPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )
        let pkg = Package(
            name: "Pkg",
            targets: [
                Target(name: "exe", dependencies: ["lib"]),
            ]
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph(["/Pkg": pkg], root: "/Pkg", diagnostics: diagnostics, in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph))
 
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
 
        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])
 
        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertEqual(lib, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", 
            "-emit-executable",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.swift.o",
        ])
    }

    func testBasicReleasePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph(["/Pkg": Package(name: "Pkg")], root: "/Pkg", diagnostics: diagnostics, in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(config: .release), graph: graph))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "3", "-O", "-j8", "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/release/ModuleCache"])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-L", "/path/to/build/release", "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable", "/path/to/build/release/exe.build/main.swift.o"])
    }

    func testBasicClangPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h",
            "/ExtPkg/Sources/extlib/extlib.c",
            "/ExtPkg/Sources/extlib/include/ext.h"
        )
        let pkg = Package(
            name: "Pkg",
            targets: [
                Target(name: "exe", dependencies: ["lib"]),
            ],
            dependencies: [
                .Package(url: "/ExtPkg", majorVersion: 1),
            ]
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph(["/Pkg": pkg, "/ExtPkg": Package(name: "ExtPkg")], root: "/Pkg", diagnostics: diagnostics, in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
 
        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let ext = try result.target(for: "extlib").clangTarget()
        var args = ["-g", "-O0"]
      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-fmodules", "-fmodule-name=extlib",
            "-I", "/ExtPkg/Sources/extlib/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(ext.basicArguments(), args)
        XCTAssertEqual(ext.objects, [AbsolutePath("/path/to/build/debug/extlib.build/extlib.c.o")])
        XCTAssertEqual(ext.moduleMap, AbsolutePath("/path/to/build/debug/extlib.build/module.modulemap"))

        let exe = try result.target(for: "exe").clangTarget()
        args = ["-g", "-O0"]
      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-fmodules", "-fmodule-name=exe",
            "-I", "/Pkg/Sources/exe/include", "-iquote", "/Pkg/Sources/lib/include", "-I", "/ExtPkg/Sources/extlib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(exe.basicArguments(), args)
        XCTAssertEqual(exe.objects, [AbsolutePath("/path/to/build/debug/exe.build/main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", 
            "/path/to/build/debug/exe.build/main.c.o",
            "/path/to/build/debug/extlib.build/extlib.c.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
    }

    func testSwiftCMixed() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )
        let pkg = Package(
            name: "Pkg",
            targets: [
                Target(name: "exe", dependencies: ["lib"]),
            ]
        )
        let graph = loadMockPackageGraph(["/Pkg": pkg], root: "/Pkg", in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        
        let lib = try result.target(for: "lib").clangTarget()
        var args = ["-g", "-O0"]
      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(lib.basicArguments(), args)
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-Xcc", "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap", "-I", "/Pkg/Sources/lib/include", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
    }

    func testTestModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/Foo/foo.swift",
            "/Pkg/Tests/LinuxMain.swift",
            "/Pkg/Tests/FooTests/foo.swift"
        )
        let graph = loadMockPackageGraph(["/Pkg": Package(name: "Pkg")], root: "/Pkg", in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
        result.checkProductsCount(1)
      #if os(macOS)
        result.checkTargetsCount(2)
      #else
        // We have an extra LinuxMain target on linux.
        result.checkTargetsCount(3)
      #endif
        
        let foo = try result.target(for: "Foo").swiftTarget().compileArguments()
        XCTAssertEqual(foo, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        let fooTests = try result.target(for: "FooTests").swiftTarget().compileArguments()
        XCTAssertEqual(fooTests, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/PkgPackageTests.xctest/Contents/MacOS/PkgPackageTests", "-module-name",
            "PkgPackageTests", "-Xlinker", "-bundle",
            "/path/to/build/debug/Foo.build/foo.swift.o",
            "/path/to/build/debug/FooTests.build/foo.swift.o",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/PkgPackageTests.xctest", "-module-name", "PkgPackageTests", "-emit-executable",
            "/path/to/build/debug/Foo.build/foo.swift.o",
            "/path/to/build/debug/FooTests.build/foo.swift.o",
            "/path/to/build/debug/PkgPackageTests.build/LinuxMain.swift.o",
        ])
      #endif
    }

    func testCModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Clibgit/module.modulemap"
        )
        let pkg = Package(
            name: "Pkg",
            dependencies: [
                .Package(url: "/Clibgit", majorVersion: 1),
            ]
        )
        let graph = loadMockPackageGraph(["/Pkg": pkg, "/Clibgit": Package(name: "Clinbgit")], root: "/Pkg", in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", "/path/to/build/debug/exe.build/main.swift.o"])
        XCTAssertEqual(try result.target(for: "exe").swiftTarget().compileArguments(), ["-swift-version", "3", "-Onone", "-g", "-enable-testing", "-j8", "-DSWIFT_PACKAGE", "-Xcc", "-fmodule-map-file=/Clibgit/module.modulemap", "-module-cache-path", "/path/to/build/debug/ModuleCache"])
    }

    func testCppModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.cpp",
            "/Pkg/Sources/lib/include/lib.h"
        )
        let pkg = Package(
            name: "Pkg",
            targets: [
                Target(name: "exe", dependencies: ["lib"]),
            ]
        )
        let graph = loadMockPackageGraph(["/Pkg": pkg], root: "/Pkg", in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        let linkArgs = try result.buildProduct(for: "exe").linkArguments()

      #if os(macOS)
        XCTAssertTrue(linkArgs.contains("-lc++"))
      #else
        XCTAssertTrue(linkArgs.contains("-lstdc++"))
      #endif
    }

    func testDynamicProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/main.swift",
            "/Bar/Source/Bar/source.swift"
        )

        typealias Package = PackageDescription4.Package

        let bar = Package(
            name: "Bar", 
            products: [
                .library(name: "Bar", type: .dynamic, targets: ["Bar"])
            ],
            targets: [
                .target(name: "Bar")
            ]
        )
        let g = loadMockPackageGraph4([
            "/Bar": bar,
            "/Foo": .init(
                name: "Foo",
                dependencies: [.package(url: "/Bar", from: "1.0.0")],
                targets: [.target(name: "Foo", dependencies: ["Bar"])],
                swiftLanguageVersions: [2, ToolsVersion.currentToolsVersion.major]),
        ], root: "/Foo", in: fs)

        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: g, fileSystem: fs))
        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let fooLinkArgs = try result.buildProduct(for: "Foo").linkArguments()
        XCTAssertEqual(fooLinkArgs,
            ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/Foo", "-module-name", "Foo", "-lBar", "-emit-executable", "/path/to/build/debug/Foo.build/main.swift.o"])

        let barLinkArgs = try result.buildProduct(for: "Bar").linkArguments()
        XCTAssertEqual(barLinkArgs,
            ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/libBar.\(MockToolchain().dynamicLibraryExtension)",
            "-module-name", "Bar", "-emit-library", "/path/to/build/debug/Bar.build/source.swift.o"])
    }

    static var allTests = [
        ("testBasicClangPackage", testBasicClangPackage),
        ("testBasicReleasePackage", testBasicReleasePackage),
        ("testBasicSwiftPackage", testBasicSwiftPackage),
        ("testCModule", testCModule),
        ("testCppModule", testCppModule),
        ("testDynamicProducts", testDynamicProducts),
        ("testSwiftCMixed", testSwiftCMixed),
        ("testTestModule", testTestModule),
    ]
}

// MARK:- Test Helpers

private enum Error: Swift.Error {
    case error(String)
}

private struct BuildPlanResult {

    let plan: BuildPlan
    let targetMap: [String: TargetDescription]
    let productMap: [String: ProductBuildDescription]

    init(plan: BuildPlan) {
        self.plan = plan
        self.productMap = Dictionary(items: plan.buildProducts.map{ ($0.product.name, $0) })
        self.targetMap = Dictionary(items: plan.targetMap.map{ ($0.0.name, $0.1) })
    }

    func checkTargetsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.targetMap.count, count, file: file, line: line)
    }

    func checkProductsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.productMap.count, count, file: file, line: line)
    }

    func target(for name: String) throws -> TargetDescription {
        guard let target = targetMap[name] else {
            throw Error.error("Target \(name) not found.")
        }
        return target
    }

    func buildProduct(for name: String) throws -> ProductBuildDescription {
        guard let product = productMap[name] else {
            // <rdar://problem/30162871> Display the thrown error on macOS
            throw Error.error("Product \(name) not found.")
        }
        return product
    }
}

fileprivate extension TargetDescription {
    func swiftTarget() throws -> SwiftTargetDescription {
        switch self {
        case .swift(let target):
            return target
        default:
            throw Error.error("Unexpected \(self) type found")
        }
    }

    func clangTarget() throws -> ClangTargetDescription {
        switch self {
        case .clang(let target):
            return target
        default:
            throw Error.error("Unexpected \(self) type")
        }
    }
}
