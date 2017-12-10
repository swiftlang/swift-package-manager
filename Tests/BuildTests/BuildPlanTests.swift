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

    
    enum EmitType: String {
        case library = "library",
        executable = "executable"
    }

    /// The j argument.
    private var j: String {
        return "-j\(SwiftCompilerTool.numThreads)"
    }

    func mockBuildParameters(
        buildPath: AbsolutePath = AbsolutePath("/path/to/build"),
        config: Build.Configuration = .debug,
        shouldLinkStaticSwiftStdlib: Bool = false
    ) -> BuildParameters {
        return BuildParameters(
            dataPath: buildPath,
            configuration: config,
            toolchain: MockToolchain(),
            flags: BuildFlags(),
            shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib)
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
        let result = BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph)
        )
 
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
 
        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])
 
        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertEqual(lib, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

      #if os(macOS)
        let linkArguments = [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe",
            "-static-stdlib", "-emit-executable",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.swift.o",
        ]
      #else
        let linkArguments = [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.swift.o",
        ]
      #endif

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), linkArguments)
    }

    func testBasicExtPackages() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Tests/ATargetTests/foo.swift",
            "/A/Tests/LinuxMain.swift",
            "/B/Sources/BTarget/foo.swift",
            "/B/Tests/BTargetTests/foo.swift",
            "/B/Tests/LinuxMain.swift"
        )

        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph4([
            "/A": Package(
                name: "A",
                dependencies: [
                    .package(url: "/B", from: "1.0.0"),
                ],
                targets: [
                    .target(name: "ATarget", dependencies: ["BLibrary"]),
                    .testTarget(name: "ATargetTests", dependencies: ["ATarget"]),
                ]),
            "/B": Package(
                name: "B",
                products: [
                    .library(name: "BLibrary", targets: ["BTarget"]),
                ],
                targets: [
                    .target(name: "BTarget", dependencies: []),
                    .testTarget(name: "BTargetTests", dependencies: ["BTarget"])
                ]),
        ], root: "/A", diagnostics: diagnostics, in: fileSystem)
        XCTAssertNoDiagnostics(diagnostics)

        let result = BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem))

        XCTAssertEqual(Set(result.productMap.keys), ["APackageTests"])
      #if os(macOS)
        XCTAssertEqual(Set(result.targetMap.keys), ["ATarget", "BTarget", "ATargetTests"])
      #else
        XCTAssertEqual(Set(result.targetMap.keys), ["ATarget", "BTarget", "APackageTests", "ATargetTests"])
      #endif
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
        XCTAssertEqual(exe, ["-swift-version", "3", "-O", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/release/ModuleCache"])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "/path/to/build/release/exe.build/main.swift.o"
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/release/exe.build/main.swift.o"
        ])
      #endif
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
        args += ["-fblocks", "-fmodules", "-fmodule-name=extlib",
            "-I", "/ExtPkg/Sources/extlib/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(ext.basicArguments(), args)
        XCTAssertEqual(ext.objects, [AbsolutePath("/path/to/build/debug/extlib.build/extlib.c.o")])
        XCTAssertEqual(ext.moduleMap, AbsolutePath("/path/to/build/debug/extlib.build/module.modulemap"))

        let exe = try result.target(for: "exe").clangTarget()
        args = ["-g", "-O0"]
      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-fblocks", "-fmodules", "-fmodule-name=exe",
            "-I", "/Pkg/Sources/exe/include", "-iquote", "/Pkg/Sources/lib/include", "-I", "/ExtPkg/Sources/extlib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(exe.basicArguments(), args)
        XCTAssertEqual(exe.objects, [AbsolutePath("/path/to/build/debug/exe.build/main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", 
            "/path/to/build/debug/exe.build/main.c.o",
            "/path/to/build/debug/extlib.build/extlib.c.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", 
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/exe.build/main.c.o",
            "/path/to/build/debug/extlib.build/extlib.c.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
      #endif
    }

    func testCLanguageStandard() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.cpp",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )
        let pkg = PackageDescription4.Package(
            name: "Pkg",
            targets: [
                .target(name: "lib"),
                .target(name: "exe", dependencies: ["lib"]),
            ],
            cLanguageStandard: .gnu99,
            cxxLanguageStandard: .cxx1z
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph4(["/Pkg": pkg], root: "/Pkg", diagnostics: diagnostics, in: fs)
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: graph, fileSystem: fs))
 
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        XCTAssertTrue(lib.basicArguments().contains("-std=gnu99"))

        let exe = try result.target(for: "exe").clangTarget()
        XCTAssertTrue(exe.basicArguments().contains("-std=c++1z"))

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-lc++", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "/path/to/build/debug/exe.build/main.cpp.o",
            "/path/to/build/debug/lib.build/lib.c.o"
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-lstdc++", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/exe.build/main.cpp.o",
            "/path/to/build/debug/lib.build/lib.c.o"
        ])
      #endif
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
        args += ["-fblocks", "-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(lib.basicArguments(), args)
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-Xcc", "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap", "-I", "/Pkg/Sources/lib/include", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/exe.build/main.swift.o",
            "/path/to/build/debug/lib.build/lib.c.o",
        ])
      #endif
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
        XCTAssertEqual(foo, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        let fooTests = try result.target(for: "FooTests").swiftTarget().compileArguments()
        XCTAssertEqual(fooTests, ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

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
            "-Xlinker", "-rpath=$ORIGIN",
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

        XCTAssertEqual(try result.target(for: "exe").swiftTarget().compileArguments(), ["-swift-version", "3", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-Xcc", "-fmodule-map-file=/Clibgit/module.modulemap", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "/path/to/build/debug/exe.build/main.swift.o"
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/exe.build/main.swift.o"
        ])
      #endif
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
        let barLinkArgs = try result.buildProduct(for: "Bar").linkArguments()

      #if os(macOS)
        XCTAssertEqual(fooLinkArgs, [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/Foo", "-module-name", "Foo", "-lBar", "-emit-executable",
            "/path/to/build/debug/Foo.build/main.swift.o"
        ])

        XCTAssertEqual(barLinkArgs, [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/libBar.dylib",
            "-module-name", "Bar", "-emit-library",
            "/path/to/build/debug/Bar.build/source.swift.o"
        ])
      #else
        XCTAssertEqual(fooLinkArgs, [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/Foo", "-module-name", "Foo", "-lBar", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/Foo.build/main.swift.o"
        ])

        XCTAssertEqual(barLinkArgs, [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/libBar.so",
            "-module-name", "Bar", "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "/path/to/build/debug/Bar.build/source.swift.o"
        ])
      #endif

    }
    
    private func assertArgsAreCorrect(_ args: [String],
                                      for moduleName: String,
                                      with dependencyStrings: [String],
                                      of type: EmitType) {
        
        XCTAssertTrue(dependencyStrings.reduce(true, { (prev, dependencyName) -> Bool in
            return prev && args.contains("-l\(dependencyName)")
        }))
        
        var suffix: String = ""
        #if os(macOS)
            XCTAssertEqual(args.suffix(2),
                           ["-emit-\(type.rawValue)",
                            "/path/to/build/debug/\(moduleName).build/\(type == .library ? "source" : "main").swift.o"
                ])
            suffix = type == .library ? ".dylib" : ""
        #else
            XCTAssertEqual(args.suffix(4),
                           ["-emit-\(type.rawValue)",
                            "-Xlinker", "-rpath=$ORIGIN",
                            "/path/to/build/debug/\(moduleName).build/\(type == .library ? "source" : "main").swift.o"
                ])
            suffix = type == .library ? ".dylib" : ""
        #endif
        XCTAssertEqual(args.prefix(8),
                       ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
                        "-o", "/path/to/build/debug/\((type == .library ? "lib" : "") + moduleName)\(suffix)", "-module-name", moduleName])
        
    }
    
    func testNthDegreeDynamicProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/main.swift",
            "/FirstOrder1/Sources/FirstOrder1/source.swift",
            "/FirstOrder2/Sources/FirstOrder2/source.swift",
            "/SecondOrder1/Sources/SecondOrder1/source.swift",
            "/SecondOrder2/Sources/SecondOrder2/source.swift",
            "/SecondOrder3/Sources/SecondOrder3/source.swift",
            "/SecondOrder4/Sources/SecondOrder4/source.swift",
            "/ThirdOrder1/Sources/ThirdOrder1/source.swift",
            "/ThirdOrder2/Sources/ThirdOrder2/source.swift",
            "/ThirdOrder3/Sources/ThirdOrder3/source.swift",
            "/ThirdOrder4/Sources/ThirdOrder4/source.swift",
            "/ThirdOrder5/Sources/ThirdOrder5/source.swift",
            "/ThirdOrder6/Sources/ThirdOrder6/source.swift",
            "/ThirdOrder7/Sources/ThirdOrder7/source.swift",
            "/ThirdOrder8/Sources/ThirdOrder8/source.swift"
        )
        
        typealias Package = PackageDescription4.Package
        
        let libraryNameGenerationSource: [(String, Int)]
            = [("First", 2), ("Second", 4), ("Third", 8)]
        
        var libraryPackages: [String: Package] = [:]
        
        let directDependencies: [String: [String]] = [
            "Foo": ["FirstOrder1", "FirstOrder2"],
            "FirstOrder1": ["SecondOrder1", "SecondOrder2"],
            "FirstOrder2": ["SecondOrder3", "SecondOrder4"],
            "SecondOrder1": ["ThirdOrder1", "ThirdOrder2"],
            "SecondOrder2": ["ThirdOrder3", "ThirdOrder4"],
            "SecondOrder3": ["ThirdOrder5", "ThirdOrder6"],
            "SecondOrder4": ["ThirdOrder7", "ThirdOrder8"]
        ]

        for criterion in libraryNameGenerationSource {
            for i in 1...(criterion.1) {
                let libraryName = "\(criterion.0)Order\(i)"
                let dependenciesByName = directDependencies[libraryName] ?? []
                
                libraryPackages["/\(libraryName)"] = Package(
                    name: libraryName,
                    products: [
                        .library(name: libraryName, type: .dynamic, targets: [libraryName])
                    ],
                    dependencies: dependenciesByName.map({ dependencyName -> Package.Dependency in
                        return Package.Dependency.package(url: "/\(dependencyName)", from: "1.0.0")
                    }),
                    targets: [
                        .target(name: libraryName, dependencies: dependenciesByName.map({ dependencyName -> PackageDescription4.Target.Dependency in
                            return PackageDescription4.Target.Dependency.init(stringLiteral: dependencyName)
                        }))
                    ],
                    swiftLanguageVersions: [2, ToolsVersion.currentToolsVersion.major]
                )
            }
        }
        
        libraryPackages["/Foo"] = .init(
            name: "Foo",
            dependencies: [.package(url: "/FirstOrder1", from: "1.0.0"),
                           .package(url: "/FirstOrder2", from: "1.0.0")],
            targets: [.target(name: "Foo", dependencies: ["FirstOrder1", "FirstOrder2"])],
            swiftLanguageVersions: [2, ToolsVersion.currentToolsVersion.major])
        
        let g = loadMockPackageGraph4(libraryPackages, root: "/Foo", in: fs)
        
        let result = BuildPlanResult(plan: try BuildPlan(buildParameters: mockBuildParameters(), graph: g, fileSystem: fs))
        result.checkProductsCount(15)
        result.checkTargetsCount(15)
        
        let fooLinkArgs = try result.buildProduct(for: "Foo").linkArguments()
        
        assertArgsAreCorrect(fooLinkArgs,
                             for: "Foo",
                             with: ["FirstOrder1", "FirstOrder2",
                                    "SecondOrder1", "SecondOrder2", "SecondOrder3", "SecondOrder4",
                                    "ThirdOrder1", "ThirdOrder2", "ThirdOrder3", "ThirdOrder4",
                                    "ThirdOrder5", "ThirdOrder6", "ThirdOrder7", "ThirdOrder8"],
                             of: .executable)
        assertArgsAreCorrect(try! result.buildProduct(for: "FirstOrder1").linkArguments(),
                             for: "FirstOrder1",
                             with: ["SecondOrder1", "SecondOrder2",
                                    "ThirdOrder1", "ThirdOrder2", "ThirdOrder3", "ThirdOrder4"],
                             of: .library)
        assertArgsAreCorrect(try! result.buildProduct(for: "FirstOrder2").linkArguments(),
                             for: "FirstOrder2",
                             with: ["SecondOrder3", "SecondOrder4",
                                    "ThirdOrder5", "ThirdOrder6", "ThirdOrder7", "ThirdOrder8"],
                             of: .library)
        assertArgsAreCorrect(try! result.buildProduct(for: "SecondOrder1").linkArguments(),
                             for: "SecondOrder1",
                             with: ["ThirdOrder1", "ThirdOrder2"],
                             of: .library)
        assertArgsAreCorrect(try! result.buildProduct(for: "SecondOrder2").linkArguments(),
                             for: "SecondOrder2",
                             with: ["ThirdOrder3", "ThirdOrder4"],
                             of: .library)
        assertArgsAreCorrect(try! result.buildProduct(for: "SecondOrder3").linkArguments(),
                             for: "SecondOrder3",
                             with: ["ThirdOrder5", "ThirdOrder6"],
                             of: .library)
        assertArgsAreCorrect(try! result.buildProduct(for: "SecondOrder4").linkArguments(),
                             for: "SecondOrder4",
                             with: ["ThirdOrder7", "ThirdOrder8"],
                             of: .library)
        for i in 1...8 {
            assertArgsAreCorrect(try! result.buildProduct(for: "ThirdOrder\(i)").linkArguments(),
                                 for: "ThirdOrder\(i)",
                                 with: [],
                                 of: .library)
        }
    }

    func testExecAsDependency() throws {
        typealias Package = PackageDescription4.Package

        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let pkg = Package(
            name: "Pkg",
            products: [
                .library(name: "lib", type: .dynamic, targets: ["lib"])
            ],
            targets: [
                .target(name: "exe"),
                .target(name: "lib", dependencies: ["exe"]),
            ]
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph4(
            ["/Pkg": pkg], root: "/Pkg", diagnostics: diagnostics, in: fs)

        let result = BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph, fileSystem: fs)
        )

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertEqual(exe, ["-swift-version", "4", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertEqual(lib, ["-swift-version", "4", "-Onone", "-g", "-enable-testing", j, "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/debug/ModuleCache"])

        #if os(macOS)
            let linkArguments = [
                "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug",
                "-o", "/path/to/build/debug/liblib.dylib", "-module-name", "lib",
                "-emit-library",
                "/path/to/build/debug/lib.build/lib.swift.o",
            ]
        #else
            let linkArguments = ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/liblib.so", "-module-name", "lib", "-emit-library", "-Xlinker", "-rpath=$ORIGIN", "/path/to/build/debug/lib.build/lib.swift.o"]
        #endif

        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), linkArguments)
    }

    func testClangTargets() throws {
        typealias Package = PackageDescription4.Package

        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/lib/include/lib.h",
            "/Pkg/Sources/lib/lib.cpp"
        )

        let pkg = Package(
            name: "Pkg",
            products: [
                .library(name: "lib", type: .dynamic, targets: ["lib"])
            ],
            targets: [
                .target(name: "exe"),
                .target(name: "lib"),
            ]
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph4(
            ["/Pkg": pkg], root: "/Pkg", diagnostics: diagnostics, in: fs)

        let result = BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs)
        )

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let exe = try result.target(for: "exe").clangTarget()
    #if os(macOS)
        XCTAssertEqual(exe.basicArguments(), ["-g", "-O0", "-fobjc-arc","-fblocks",  "-fmodules", "-fmodule-name=exe", "-I", "/Pkg/Sources/exe/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"])
    #else
        XCTAssertEqual(exe.basicArguments(), ["-g", "-O0","-fblocks",  "-fmodules", "-fmodule-name=exe", "-I", "/Pkg/Sources/exe/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"])
    #endif
        XCTAssertEqual(exe.objects, [AbsolutePath("/path/to/build/debug/exe.build/main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        let lib = try result.target(for: "lib").clangTarget()
    #if os(macOS)
        XCTAssertEqual(lib.basicArguments(), ["-g", "-O0", "-fobjc-arc","-fblocks",  "-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"])
    #else
        XCTAssertEqual(lib.basicArguments(), ["-g", "-O0","-fblocks",  "-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"])
    #endif
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.cpp.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

    #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), ["/fake/path/to/swiftc", "-lc++", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/liblib.dylib", "-module-name", "lib", "-emit-library", "/path/to/build/debug/lib.build/lib.cpp.o"])
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", "/path/to/build/debug/exe.build/main.c.o"])
    #else
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), ["/fake/path/to/swiftc", "-lstdc++", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/liblib.so", "-module-name", "lib", "-emit-library", "-Xlinker", "-rpath=$ORIGIN", "/path/to/build/debug/lib.build/lib.cpp.o"])
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-g", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", "-Xlinker", "-rpath=$ORIGIN", "/path/to/build/debug/exe.build/main.c.o"])
    #endif
    }

    static var allTests = [
        ("testBasicClangPackage", testBasicClangPackage),
        ("testBasicExtPackages", testBasicExtPackages),
        ("testBasicReleasePackage", testBasicReleasePackage),
        ("testBasicSwiftPackage", testBasicSwiftPackage),
        ("testCModule", testCModule),
        ("testCLanguageStandard", testCLanguageStandard),
        ("testCppModule", testCppModule),
        ("testDynamicProducts", testDynamicProducts),
        ("testSwiftCMixed", testSwiftCMixed),
        ("testTestModule", testTestModule),
        ("testExecAsDependency", testExecAsDependency),
        ("testClangTargets", testClangTargets),
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
