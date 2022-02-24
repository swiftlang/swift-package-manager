/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
@testable import Build
@testable import PackageLoading
import PackageModel
import SPMBuildCore
import SPMTestSupport
import SwiftDriver
import TSCBasic
import Workspace
import XCTest

import struct TSCUtility.BuildFlags
import enum TSCUtility.Diagnostics
import struct TSCUtility.Triple

let hostTriple = UserToolchain.default.triple
#if os(macOS)
    let defaultTargetTriple: String = hostTriple.tripleString(forPlatformVersion: "10.10")
#else
    let defaultTargetTriple: String = hostTriple.tripleString
#endif

private struct MockToolchain: SPMBuildCore.Toolchain {
    let swiftCompiler = AbsolutePath("/fake/path/to/swiftc")
    let extraCCFlags: [String] = []
    let extraSwiftCFlags: [String] = []
    #if os(macOS)
    let extraCPPFlags: [String] = ["-lc++"]
    #else
    let extraCPPFlags: [String] = ["-lstdc++"]
    #endif
    func getClangCompiler() throws -> AbsolutePath {
        return AbsolutePath("/fake/path/to/clang")
    }

    func _isClangCompilerVendorApple() throws -> Bool? {
      #if os(macOS)
        return true
      #else
        return false
      #endif
    }
}

final class BuildPlanTests: XCTestCase {
    let inputsDir = AbsolutePath(#file).parentDirectory.appending(components: "Inputs")

    /// The j argument.
    private var j: String {
        return "-j3"
    }

    func mockBuildParameters(
        buildPath: AbsolutePath = AbsolutePath("/path/to/build"),
        config: BuildConfiguration = .debug,
        toolchain: SPMBuildCore.Toolchain = MockToolchain(),
        flags: BuildFlags = BuildFlags(),
        shouldLinkStaticSwiftStdlib: Bool = false,
        canRenameEntrypointFunctionName: Bool = false,
        destinationTriple: TSCUtility.Triple = hostTriple,
        indexStoreMode: BuildParameters.IndexStoreMode = .off,
        useExplicitModuleBuild: Bool = false,
        linkerDeadStrip: Bool = true
    ) -> BuildParameters {
        return BuildParameters(
            dataPath: buildPath,
            configuration: config,
            toolchain: toolchain,
            hostTriple: hostTriple,
            destinationTriple: destinationTriple,
            flags: flags,
            jobs: 3,
            shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
            canRenameEntrypointFunctionName: canRenameEntrypointFunctionName,
            indexStoreMode: indexStoreMode,
            useExplicitModuleBuild: useExplicitModuleBuild,
            linkerDeadStrip: linkerDeadStrip
        )
    }

    func mockBuildParameters(environment: BuildEnvironment) -> BuildParameters {
        let triple: TSCUtility.Triple
        switch environment.platform {
        case .macOS:
            triple = Triple.macOS
        case .linux:
            triple = Triple.arm64Linux
        case .android:
            triple = Triple.arm64Android
        case .windows:
            triple = Triple.windows
        default:
            fatalError("unsupported platform in tests")
        }

        return mockBuildParameters(config: environment.configuration, destinationTriple: triple)
    }

    func testBasicSwiftPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

      #if os(macOS)
        let linkArguments = [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple, "-Xlinker", "-add_ast_path",
            "-Xlinker", "/path/to/build/debug/exe.build/exe.swiftmodule", "-Xlinker", "-add_ast_path",
            "-Xlinker", "/path/to/build/debug/lib.swiftmodule",
        ]
      #else
        let linkArguments = [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe",
            "-static-stdlib", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ]
      #endif

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), linkArguments)

      #if os(macOS)
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("can be downloaded"), severity: .warning)
        }
      #else
        XCTAssertNoDiagnostics(observability.diagnostics)
      #endif
    }

    func testExplicitSwiftPackageBuild() throws {
        // <rdar://82053045> Fix and re-enable SwiftPM test `testExplicitSwiftPackageBuild`
        try XCTSkipIf(true)
        try withTemporaryDirectory { path in
            // Create a test package with three targets:
            // A -> B -> C
            let fs = localFileSystem
            try fs.changeCurrentWorkingDirectory(to: path)
            let testDirPath = path.appending(component: "ExplicitTest")
            let buildDirPath = path.appending(component: ".build")
            let sourcesPath = testDirPath.appending(component: "Sources")
            let aPath = sourcesPath.appending(component: "A")
            let bPath = sourcesPath.appending(component: "B")
            let cPath = sourcesPath.appending(component: "C")
            try fs.createDirectory(testDirPath)
            try fs.createDirectory(buildDirPath)
            try fs.createDirectory(sourcesPath)
            try fs.createDirectory(aPath)
            try fs.createDirectory(bPath)
            try fs.createDirectory(cPath)
            let main = aPath.appending(component: "main.swift")
            let aSwift = aPath.appending(component: "A.swift")
            let bSwift = bPath.appending(component: "B.swift")
            let cSwift = cPath.appending(component: "C.swift")
            try localFileSystem.writeFileContents(main) {
              $0 <<< "baz();"
            }
            try localFileSystem.writeFileContents(aSwift) {
                $0 <<< "import B;"
                $0 <<< "import C;"
                $0 <<< "public func baz() { bar() }"
            }
            try localFileSystem.writeFileContents(bSwift) {
                $0 <<< "import C;"
                $0 <<< "public func bar() { foo() }"
            }
            try localFileSystem.writeFileContents(cSwift) {
                $0 <<< "public func foo() {}"
            }

            // Plan package build with explicit module build
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fs: fs,
                manifests: [
                    Manifest.createRootManifest(
                        name: "ExplicitTest",
                        path: testDirPath,
                        targets: [
                            TargetDescription(name: "A", dependencies: ["B"]),
                            TargetDescription(name: "B", dependencies: ["C"]),
                            TargetDescription(name: "C", dependencies: []),
                        ]),
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            do {
                let plan = try BuildPlan(
                    buildParameters: mockBuildParameters(
                        buildPath: buildDirPath,
                        config: .release,
                        toolchain: UserToolchain.default,
                        destinationTriple: UserToolchain.default.triple,
                        useExplicitModuleBuild: true
                    ),
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )


                let yaml = buildDirPath.appending(component: "release.yaml")
                let llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
                try llbuild.generateManifest(at: yaml)
                let contents: String = try localFileSystem.readFileContents(yaml)

                // A few basic checks
                XCTAssertMatch(contents, .contains("-disable-implicit-swift-modules"))
                XCTAssertMatch(contents, .contains("-fno-implicit-modules"))
                XCTAssertMatch(contents, .contains("-explicit-swift-module-map-file"))
                XCTAssertMatch(contents, .contains("A-dependencies"))
                XCTAssertMatch(contents, .contains("B-dependencies"))
                XCTAssertMatch(contents, .contains("C-dependencies"))
            } catch Driver.Error.unableToDecodeFrontendTargetInfo {
                // If the toolchain being used is sufficiently old, the integrated driver
                // will not be able to parse the `-print-target-info` output. In which case,
                // we cannot yet rely on the integrated swift driver.
                // This effectively guards the test from running on unupported, older toolchains.
                throw XCTSkip()
            }
        }
    }

    func testSwiftConditionalDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/PkgLib/lib.swift",
            "/ExtPkg/Sources/ExtLib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ExtPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            ))
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtLib", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            ))
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    name: "ExtPkg",
                    path: .init("/ExtPkg"),
                    products: [
                        ProductDescription(name: "ExtLib", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        do {
            let plan = try BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let linkedFileList: String = try fs.readFileContents(AbsolutePath("/path/to/build/release/exe.product/Objects.LinkFileList"))
            XCTAssertMatch(linkedFileList, .contains("PkgLib"))
            XCTAssertNoMatch(linkedFileList, .contains("ExtLib"))

            let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "release.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            XCTAssertMatch(contents, .contains("""
                    inputs: ["/Pkg/Sources/exe/main.swift","/path/to/build/release/PkgLib.swiftmodule"]
                """))

        }

        do {
            let plan = try BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let linkedFileList: String = try fs.readFileContents(AbsolutePath("/path/to/build/debug/exe.product/Objects.LinkFileList"))
            XCTAssertNoMatch(linkedFileList, .contains("PkgLib"))
            XCTAssertNoMatch(linkedFileList, .contains("ExtLib"))

            let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            XCTAssertMatch(contents, .contains("""
                    inputs: ["/Pkg/Sources/exe/main.swift"]
                """))
        }
    }

    func testBasicExtPackages() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Tests/ATargetTests/foo.swift",
            "/B/Sources/BTarget/foo.swift",
            "/B/Tests/BTargetTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                        TargetDescription(name: "ATargetTests", dependencies: ["ATarget"], type: .test),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "B",
                    path: .init("/B"),
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                        TargetDescription(name: "BTargetTests", dependencies: ["BTarget"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        XCTAssertEqual(Set(result.productMap.keys), ["APackageTests"])
      #if os(macOS)
        XCTAssertEqual(Set(result.targetMap.keys), ["ATarget", "BTarget", "ATargetTests"])
      #else
        XCTAssertEqual(Set(result.targetMap.keys), [
            "APackageTests",
            "ATarget",
            "ATargetTests",
            "BTarget"
        ])
      #endif
    }

    func testBasicReleasePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/release/ModuleCache", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-dead_strip", "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/release/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "--gc-sections", "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/release/exe.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testBasicReleasePackageNoDeadStrip() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release, linkerDeadStrip: false),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/release/ModuleCache", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/release/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/release/exe.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testBasicClangPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/lib.S",
            "/Pkg/Sources/lib/include/lib.h",
            "/ExtPkg/Sources/extlib/extlib.c",
            "/ExtPkg/Sources/extlib/include/ext.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ExtPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["ExtPkg"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "ExtPkg",
                    path: .init("/ExtPkg"),
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["extlib"]),
                    ],
                    targets: [
                        TargetDescription(name: "extlib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let ext = try result.target(for: "extlib").clangTarget()
        var args: [String] = []

      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-target", defaultTargetTriple]
        args += ["-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks", "-fmodules", "-fmodule-name=extlib",
            "-I", "/ExtPkg/Sources/extlib/include", "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(try ext.basicArguments(isCXX: false), args)
        XCTAssertEqual(ext.objects, [AbsolutePath("/path/to/build/debug/extlib.build/extlib.c.o")])
        XCTAssertEqual(ext.moduleMap, AbsolutePath("/path/to/build/debug/extlib.build/module.modulemap"))

        let exe = try result.target(for: "exe").clangTarget()
        args = []

      #if os(macOS)
        args += ["-fobjc-arc", "-target", defaultTargetTriple]
      #else
        args += ["-target", defaultTargetTriple]
      #endif

        args += ["-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks", "-fmodules", "-fmodule-name=exe",
            "-I", "/Pkg/Sources/exe/include", "-I", "/Pkg/Sources/lib/include",
            "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap",
            "-I", "/ExtPkg/Sources/extlib/include",
            "-fmodule-map-file=/path/to/build/debug/extlib.build/module.modulemap",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache",
        ]
        XCTAssertEqual(try exe.basicArguments(isCXX: false), args)
        XCTAssertEqual(exe.objects, [AbsolutePath("/path/to/build/debug/exe.build/main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #endif

      let linkedFileList: String = try fs.readFileContents(AbsolutePath("/path/to/build/debug/exe.product/Objects.LinkFileList"))
      XCTAssertEqual(linkedFileList, """
          /path/to/build/debug/exe.build/main.c.o
          /path/to/build/debug/extlib.build/extlib.c.o
          /path/to/build/debug/lib.build/lib.c.o

          """)
    }

    func testClangConditionalDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/PkgLib/lib.c",
            "/Pkg/Sources/PkgLib/lib.S",
            "/Pkg/Sources/PkgLib/include/lib.h",
            "/ExtPkg/Sources/ExtLib/extlib.c",
            "/ExtPkg/Sources/ExtLib/include/ext.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/ExtPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            ))
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtPkg", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            ))
                        ]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    name: "ExtPkg",
                    path: .init("/ExtPkg"),
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        do {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exeArguments = try result.target(for: "exe").clangTarget().basicArguments(isCXX: false)
            XCTAssert(exeArguments.contains { $0.contains("PkgLib") })
            XCTAssert(exeArguments.allSatisfy { !$0.contains("ExtLib") })

            let libArguments = try result.target(for: "PkgLib").clangTarget().basicArguments(isCXX: false)
            XCTAssert(libArguments.allSatisfy { !$0.contains("ExtLib") })
        }

        do {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let arguments = try result.target(for: "exe").clangTarget().basicArguments(isCXX: false)
            XCTAssert(arguments.allSatisfy { !$0.contains("PkgLib") && !$0.contains("ExtLib")  })

            let libArguments = try result.target(for: "PkgLib").clangTarget().basicArguments(isCXX: false)
            XCTAssert(libArguments.contains { $0.contains("ExtLib") })
        }
    }

    func testCLanguageStandard() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.cpp",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/libx.cpp",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    cLanguageStandard: "gnu99",
                    cxxLanguageStandard: "c++1z",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-lc++", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-lstdc++", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #endif


        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains(#"-std=gnu99","-c","/Pkg/Sources/lib/lib.c"#))
        XCTAssertMatch(contents, .contains(#"-std=c++1z","-c","/Pkg/Sources/lib/libx.cpp"#))
    }

    func testSwiftCMixed() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        var args: [String] = []

      #if os(macOS)
        args += ["-fobjc-arc", "-target", defaultTargetTriple]
      #else
        args += ["-target", defaultTargetTriple]
      #endif

        args += ["-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks", "-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc", "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap", "-Xcc", "-I", "-Xcc", "/Pkg/Sources/lib/include", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/exe.build/exe.swiftmodule",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testSwiftCAsmMixed() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/lib.S",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    toolsVersion: .v5,
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        XCTAssertEqual(lib.objects, [
            AbsolutePath("/path/to/build/debug/lib.build/lib.S.o"),
            AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")
        ])
    }

    func testREPLArguments() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/swiftlib/lib.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h",
            "/Dep/Sources/Dep/dep.swift",
            "/Dep/Sources/CDep/cdep.c",
            "/Dep/Sources/CDep/include/head.h",
            "/Dep/Sources/CDep/include/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/Dep"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["swiftlib"]),
                        TargetDescription(name: "swiftlib", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["Dep"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Dep",
                    path: .init("/Dep"),
                    products: [
                        ProductDescription(name: "Dep", type: .library(.automatic), targets: ["Dep"]),
                    ],
                    targets: [
                        TargetDescription(name: "Dep", dependencies: ["CDep"]),
                        TargetDescription(name: "CDep", dependencies: []),
                    ]),
            ],
            createREPLProduct: true,
                                         observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        XCTAssertEqual(plan.createREPLArguments().sorted(), ["-I/Dep/Sources/CDep/include", "-I/path/to/build/debug", "-I/path/to/build/debug/lib.build", "-L/path/to/build/debug", "-lpkg__REPL"])

        XCTAssertEqual(plan.graph.allProducts.map({ $0.name }).sorted(), [
            "Dep",
            "exe",
            "pkg__REPL"
        ])
    }

    func testTestModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/Foo/foo.swift",
            "/Pkg/Tests/\(SwiftTarget.testManifestNames.first!).swift",
            "/Pkg/Tests/FooTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
      #if os(macOS)
        result.checkTargetsCount(2)
      #else
        // We have an extra test discovery target on linux.
        result.checkTargetsCount(3)
      #endif

        let foo = try result.target(for: "Foo").swiftTarget().compileArguments()
        XCTAssertMatch(foo, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

        let fooTests = try result.target(for: "FooTests").swiftTarget().compileArguments()
        XCTAssertMatch(fooTests, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

      #if os(macOS)
        let version = MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/PkgPackageTests.xctest/Contents/MacOS/PkgPackageTests", "-module-name",
            "PkgPackageTests", "-Xlinker", "-bundle",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../",
            "@/path/to/build/debug/PkgPackageTests.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", "\(hostTriple.tripleString(forPlatformVersion: version))",
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/Foo.swiftmodule",
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/FooTests.swiftmodule",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/PkgPackageTests.xctest", "-module-name", "PkgPackageTests", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/PkgPackageTests.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testConcurrencyInOS() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "12.0"),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "/path/to/build/release/ModuleCache", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-g", "-L", "/path/to/build/release",
            "-o", "/path/to/build/release/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-dead_strip", "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/release/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-target", hostTriple.tripleString(forPlatformVersion: "12.0"),
        ])
      #endif
    }

    func testParseAsLibraryFlagForExe() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            // First executable has a single source file not named `main.swift`.
            "/Pkg/Sources/exe1/foo.swift",
            // Second executable has a single source file named `main.swift`.
            "/Pkg/Sources/exe2/main.swift",
            // Third executable has multiple source files.
            "/Pkg/Sources/exe3/bar.swift",
            "/Pkg/Sources/exe3/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    toolsVersion: .v5_5,
                    targets: [
                        TargetDescription(name: "exe1", type: .executable),
                        TargetDescription(name: "exe2", type: .executable),
                        TargetDescription(name: "exe3", type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(3)
        result.checkTargetsCount(3)

        XCTAssertNoDiagnostics(observability.diagnostics)

        // Check that the first target (single source file not named main) has -parse-as-library.
        let exe1 = try result.target(for: "exe1").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe1, ["-parse-as-library"])

        // Check that the second target (single source file named main) does not have -parse-as-library.
        let exe2 = try result.target(for: "exe2").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe2, ["-parse-as-library"])

        // Check that the third target (multiple source files) does not have -parse-as-library.
        let exe3 = try result.target(for: "exe3").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe3, ["-parse-as-library"])
    }

    func testCModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Clibgit/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/Clibgit"), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "Clibgit",
                    path: .init("/Clibgit")
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        XCTAssertMatch(try result.target(for: "exe").swiftTarget().compileArguments(), ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-Xcc", "-fmodule-map-file=/Clibgit/module.modulemap", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/exe.build/exe.swiftmodule",
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testCppModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.cpp",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        let linkArgs = try result.buildProduct(for: "exe").linkArguments()

      #if os(macOS)
        XCTAssertMatch(linkArgs, ["-lc++"])
      #else
        XCTAssertMatch(linkArgs, ["-lstdc++"])
      #endif
    }

    func testDynamicProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/main.swift",
            "/Bar/Source/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "Bar",
                    path: .init("/Bar"),
                    products: [
                        ProductDescription(name: "Bar-Baz", type: .library(.dynamic), targets: ["Bar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init("/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar-Baz"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: g,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let fooLinkArgs = try result.buildProduct(for: "Foo").linkArguments()
        let barLinkArgs = try result.buildProduct(for: "Bar-Baz").linkArguments()

      #if os(macOS)
        XCTAssertEqual(fooLinkArgs, [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
           "-o", "/path/to/build/debug/Foo", "-module-name", "Foo", "-lBar-Baz", "-emit-executable",
           "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/Foo.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/Foo.build/Foo.swiftmodule"
        ])

        XCTAssertEqual(barLinkArgs, [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/libBar-Baz.dylib",
            "-module-name", "Bar_Baz", "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/libBar-Baz.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@/path/to/build/debug/Bar-Baz.product/Objects.LinkFileList",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/Bar.swiftmodule"
        ])
      #else
        XCTAssertEqual(fooLinkArgs, [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
            "-o", "/path/to/build/debug/Foo", "-module-name", "Foo", "-lBar-Baz", "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/Foo.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])

        XCTAssertEqual(barLinkArgs, [
            "/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o",
            "/path/to/build/debug/libBar-Baz.so",
            "-module-name", "Bar_Baz", "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@/path/to/build/debug/Bar-Baz.product/Objects.LinkFileList",
            "-target", defaultTargetTriple,
        ])
      #endif

      #if os(macOS)
        XCTAssert(
            barLinkArgs.contains("-install_name")
                && barLinkArgs.contains("@rpath/libBar-Baz.dylib")
                && barLinkArgs.contains("-rpath")
                && barLinkArgs.contains("@loader_path"),
            "The dynamic library will not work once moved outside the build directory."
        )
      #endif
    }

    func testExecAsDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

        #if os(macOS)
            let linkArguments = [
                "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
                "-o", "/path/to/build/debug/liblib.dylib", "-module-name", "lib",
                "-emit-library",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib",
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
                "@/path/to/build/debug/lib.product/Objects.LinkFileList",
                "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift/macosx",
                "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
                "-target", defaultTargetTriple,
                "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/lib.swiftmodule",
            ]
        #else
            let linkArguments = [
                "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
                "-o", "/path/to/build/debug/liblib.so", "-module-name", "lib",
                "-emit-library", "-Xlinker", "-rpath=$ORIGIN",
                "@/path/to/build/debug/lib.product/Objects.LinkFileList",
                "-target", defaultTargetTriple,
            ]
        #endif

        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), linkArguments)
    }

    func testClangTargets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/lib/include/lib.h",
            "/Pkg/Sources/lib/lib.cpp"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)
        
        let triple = mockBuildParameters().triple

        let exe = try result.target(for: "exe").clangTarget()
        
        var expectedExeBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedExeBasicArgs += ["-target", defaultTargetTriple, "-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
        expectedExeBasicArgs += ["-fmodules", "-fmodule-name=exe"]
        expectedExeBasicArgs += ["-I", "/Pkg/Sources/exe/include"]
        expectedExeBasicArgs += ["-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        XCTAssertEqual(try exe.basicArguments(isCXX: false), expectedExeBasicArgs)
        XCTAssertEqual(exe.objects, [AbsolutePath("/path/to/build/debug/exe.build/main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        let lib = try result.target(for: "lib").clangTarget()
        
        var expectedLibBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedLibBasicArgs += ["-target", defaultTargetTriple, "-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
        let shouldHaveModules = !(triple.isDarwin() || triple.isWindows() || triple.isAndroid())
        if shouldHaveModules {
            expectedLibBasicArgs += ["-fmodules", "-fmodule-name=lib"]
        }
        expectedLibBasicArgs += ["-I", "/Pkg/Sources/lib/include"]
        if shouldHaveModules {
            expectedLibBasicArgs += ["-fmodules-cache-path=/path/to/build/debug/ModuleCache"]
        }
        XCTAssertEqual(try lib.basicArguments(isCXX: true), expectedLibBasicArgs)

        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.cpp.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

    #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), ["/fake/path/to/swiftc", "-lc++", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/liblib.dylib", "-module-name", "lib", "-emit-library", "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib", "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "@/path/to/build/debug/lib.product/Objects.LinkFileList", "-runtime-compatibility-version", "none", "-target", defaultTargetTriple])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "@/path/to/build/debug/exe.product/Objects.LinkFileList", "-runtime-compatibility-version", "none", "-target", defaultTargetTriple])
    #else
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), ["/fake/path/to/swiftc", "-lstdc++", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/liblib.so", "-module-name", "lib", "-emit-library", "-Xlinker", "-rpath=$ORIGIN", "@/path/to/build/debug/lib.product/Objects.LinkFileList", "-runtime-compatibility-version", "none", "-target", defaultTargetTriple])
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), ["/fake/path/to/swiftc", "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe", "-module-name", "exe", "-emit-executable", "-Xlinker", "-rpath=$ORIGIN", "@/path/to/build/debug/exe.product/Objects.LinkFileList", "-runtime-compatibility-version", "none", "-target", defaultTargetTriple])
    #endif
    }

    func testNonReachableProductsAndTargets() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/BTarget1.swift",
            "/B/Sources/BTarget2/main.swift",
            "/C/Sources/CTarget/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/C"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "aexec", type: .executable, targets: ["ATarget"])
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "B",
                    path: .init("/B"),
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.static), targets: ["BTarget1"]),
                        ProductDescription(name: "bexec", type: .executable, targets: ["BTarget2"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget1", dependencies: []),
                        TargetDescription(name: "BTarget2", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "C",
                    path: .init("/C"),
                    products: [
                        ProductDescription(name: "cexec", type: .executable, targets: ["CTarget"])
                    ],
                    targets: [
                        TargetDescription(name: "CTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        XCTAssertEqual(observability.diagnostics.count, 1)
        let firstDiagnostic = observability.diagnostics.first.map({ $0.message })
        XCTAssert(
            firstDiagnostic == "dependency 'c' is not used by any target",
            "Unexpected diagnostic: " + (firstDiagnostic ?? "[none]")
        )
        #endif

        let graphResult = PackageGraphResult(graph)
        graphResult.check(reachableProducts: "aexec", "BLibrary")
        graphResult.check(reachableTargets: "ATarget", "BTarget1")
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        graphResult.check(products: "aexec", "BLibrary")
        graphResult.check(targets: "ATarget", "BTarget1")
        #else
        graphResult.check(products: "BLibrary", "bexec", "aexec", "cexec")
        graphResult.check(targets: "ATarget", "BTarget1", "BTarget2", "CTarget")
        #endif

        let planResult = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        planResult.checkProductsCount(2)
        planResult.checkTargetsCount(2)
        #else
        planResult.checkProductsCount(4)
        planResult.checkTargetsCount(4)
        #endif
    }

    func testReachableBuildProductsAndTargets() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/source.swift",
            "/B/Sources/BTarget2/source.swift",
            "/B/Sources/BTarget3/source.swift",
            "/C/Sources/CTarget/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/C"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "aexec", type: .executable, targets: ["ATarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: [
                            .product(name: "BLibrary1", package: "B", condition: PackageConditionDescription(
                                platformNames: ["linux"],
                                config: nil
                            )),
                            .product(name: "BLibrary2", package: "B", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                            .product(name: "CLibrary", package: "C", condition: PackageConditionDescription(
                                platformNames: ["android"],
                                config: "release"
                            )),
                        ])
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    name: "B",
                    path: .init("/B"),
                    products: [
                        ProductDescription(name: "BLibrary1", type: .library(.static), targets: ["BTarget1"]),
                        ProductDescription(name: "BLibrary2", type: .library(.static), targets: ["BTarget2"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget1", dependencies: []),
                        TargetDescription(name: "BTarget2", dependencies: [
                            .target(name: "BTarget3", condition: PackageConditionDescription(
                                platformNames: ["macos"],
                                config: nil
                            )),
                        ]),
                        TargetDescription(name: "BTarget3", dependencies: []),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    name: "C",
                    path: .init("/C"),
                    products: [
                        ProductDescription(name: "CLibrary", type: .library(.static), targets: ["CTarget"])
                    ],
                    targets: [
                        TargetDescription(name: "CTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        let graphResult = PackageGraphResult(graph)

        do {
            let linuxDebug = BuildEnvironment(platform: .linux, configuration: .debug)
            try graphResult.check(reachableBuildProducts: "aexec", "BLibrary1", "BLibrary2", in: linuxDebug)
            try graphResult.check(reachableBuildTargets: "ATarget", "BTarget1", "BTarget2", in: linuxDebug)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: linuxDebug),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }

        do {
            let macosDebug = BuildEnvironment(platform: .macOS, configuration: .debug)
            try graphResult.check(reachableBuildProducts: "aexec", "BLibrary2", in: macosDebug)
            try graphResult.check(reachableBuildTargets: "ATarget", "BTarget2", "BTarget3", in: macosDebug)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: macosDebug),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }

        do {
            let androidRelease = BuildEnvironment(platform: .android, configuration: .release)
            try graphResult.check(reachableBuildProducts: "aexec", "CLibrary", in: androidRelease)
            try graphResult.check(reachableBuildTargets: "ATarget", "CTarget", in: androidRelease)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: androidRelease),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }
    }

    func testModuleAliasingDirectDeps() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/fooPkg/Sources/Logging/fileLogging.swift",
                                        "/barPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Foo",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]
                                                                 ),
                                                         .product(name: "Bar",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 )
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" && $0.target.moduleAliases?["Logging"] == "BarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        
        let fooLoggingArgs = try result.target(for: "FooLogging").swiftTarget().compileArguments()
        let barLoggingArgs = try result.target(for: "BarLogging").swiftTarget().compileArguments()
        let loggingArgs = try result.target(for: "Logging").swiftTarget().compileArguments()
        #if os(macOS)
        XCTAssertMatch(fooLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/FooLogging.build/FooLogging-Swift.h", .anySequence])
        XCTAssertMatch(barLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/BarLogging.build/BarLogging-Swift.h", .anySequence])
        XCTAssertMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #else
        XCTAssertNoMatch(fooLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/FooLogging.build/FooLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(barLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/BarLogging.build/BarLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #endif
    }

    func testModuleAliasingDuplicateTargetNameInUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/otherPkg/Sources/Utils/fileUtils.swift",
                                        "/otherPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "otherPkg",
                    path: .init("/otherPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/otherPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "OtherLogging"])]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "OtherLogging" && $0.target.moduleAliases?["Logging"] == "OtherLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "OtherLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })

        let otherLoggingArgs = try result.target(for: "OtherLogging").swiftTarget().compileArguments()
        let loggingArgs = try result.target(for: "Logging").swiftTarget().compileArguments()
        
        #if os(macOS)
        XCTAssertMatch(otherLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/OtherLogging.build/OtherLogging-Swift.h", .anySequence])
        XCTAssertMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #else
        XCTAssertNoMatch(otherLoggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/OtherLogging.build/OtherLogging-Swift.h", .anySequence])
        XCTAssertNoMatch(loggingArgs, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Logging.build/Logging-Swift.h", .anySequence])
        #endif
    }

    func testModuleAliasingMultipleAliasesInProduct() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                        "/thisPkg/Sources/Logging/file.swift",
                                        "/otherPkg/Sources/Utils/fileUtils.swift",
                                        "/otherPkg/Sources/Logging/fileLogging.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let _ = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "otherPkg",
                    path: .init("/otherPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                        ProductDescription(name: "LoggingProd", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils", dependencies: ["Logging"]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/otherPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "UtilsLogging"]),
                                                         .product(name: "LoggingProd",
                                                                  package: "otherPkg",
                                                                  moduleAliases: ["Logging": "OtherLogging"])]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertTrue(observability.diagnostics.contains(where: {
            $0.message.contains("multiple aliases: ['UtilsLogging', 'OtherLogging'] found for target 'Logging' in product 'LoggingProd' from package 'otherPkg'")
        }), "expected multiple aliases diagnostics")
    }

    func testModuleAliasingDuplicateTargetNameInNestedUpstream() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging", package: "barPkg")]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"])
                                          ]),
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingOverrideMultipleAliases() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/Logging/file1.swift",
                                    "/thisPkg/Sources/Math/file2.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/barPkg/Sources/Math/fileMath.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "LoggingProd", type: .library(.automatic), targets: ["Logging"]),
                        ProductDescription(name: "MathProd", type: .library(.automatic), targets: ["Math"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Math", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "LoggingProd",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Logging": "BarLogging"]
                                                                 ),
                                                         .product(name: "MathProd",
                                                                  package: "barPkg",
                                                                  moduleAliases: ["Math": "BarMath"])
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["Logging",
                                                         "Math",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging", "Math": "FooMath"])
                                                        ]),
                        TargetDescription(name: "Logging", dependencies: []),
                        TargetDescription(name: "Math", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(6)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" && $0.target.moduleAliases?["Math"] == "FooMath" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "BarLogging" && $0.target.moduleAliases?["Logging"] == "BarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooMath" && $0.target.moduleAliases?["Math"] == "FooMath" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "BarMath" && $0.target.moduleAliases?["Math"] == "BarMath" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Math" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingSameTargetFromUpstreamWithoutAlias() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/MyLogging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "barPkg"
                                                                 )]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["MyLogging",
                                                         .product(name: "Utils",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]),
                                                         .product(name: "Logging",
                                                                  package: "barPkg")
                                          ]),
                        TargetDescription(name: "MyLogging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Utils" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "MyLogging" && $0.target.moduleAliases == nil })
    }

    func testModuleAliasingDuplicateTargetNamesFromMultiplePkgs() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/thisPkg/Sources/MyLogging/file.swift",
                                    "/fooPkg/Sources/Utils/fileUtils.swift",
                                    "/barPkg/Sources/Logging/fileLogging.swift",
                                    "/carPkg/Sources/Logging/fileLogging.swift"
        )
        
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "carPkg",
                    path: .init("/carPkg"),
                    products: [
                        ProductDescription(name: "CarLog", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "barPkg",
                    path: .init("/barPkg"),
                    products: [
                        ProductDescription(name: "BarLog", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "fooPkg",
                    path: .init("/fooPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "UtilsProd", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils",
                                          dependencies: [.product(name: "BarLog",
                                                                  package: "barPkg"
                                                                 )]),
                    ]),
                Manifest.createRootManifest(
                    name: "thisPkg",
                    path: .init("/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init("/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init("/carPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: ["MyLogging",
                                                         .product(name: "UtilsProd",
                                                                  package: "fooPkg",
                                                                  moduleAliases: ["Logging": "FooLogging"]),
                                                         .product(name: "CarLog",
                                                                  package: "carPkg",
                                                                  moduleAliases: ["Logging": "CarLogging"])
                                          ]),
                        TargetDescription(name: "MyLogging", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        
        result.checkProductsCount(1)
        result.checkTargetsCount(5)
        
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" && $0.target.moduleAliases?["Logging"] == "FooLogging" })
        XCTAssertFalse(result.targetMap.values.contains { $0.target.name == "Logging" && $0.target.moduleAliases == nil })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "CarLogging" && $0.target.moduleAliases?["Logging"] == "CarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { arg in
            return arg.target.name == "Utils" &&
            arg.target.moduleAliases?["Logging"] == "FooLogging"
        })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "MyLogging" && $0.target.moduleAliases == nil })
    }

    func testSystemPackageBuildPlan() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg")
                )
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(BuildPlan.Error.noBuildableTarget) {
            _ = try BuildPlan(
                buildParameters: mockBuildParameters(),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
        }
    }

    func testPkgConfigHintDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BTarget"]),
                        TargetDescription(
                            name: "BTarget",
                            type: .system,
                            pkgConfig: "BTarget",
                            providers: [
                                .brew(["BTarget"]),
                                .apt(["BTarget"]),
                                .yum(["BTarget"]),
                            ]
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        _ = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

        XCTAssertTrue(observability.diagnostics.contains(where: {
            $0.severity == .warning &&
            $0.message.hasPrefix("you may be able to install BTarget using your system-packager")
        }), "expected PkgConfigHint diagnostics")
    }

    func testPkgConfigGenericDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BTarget"]),
                        TargetDescription(
                            name: "BTarget",
                            type: .system,
                            pkgConfig: "BTarget"
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        _ = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

        let diagnostic = observability.diagnostics.last!

        XCTAssertEqual(diagnostic.message, "couldn't find pc file for BTarget")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.metadata?.targetName, "BTarget")
        XCTAssertEqual(diagnostic.metadata?.pcFile, "BTarget.pc")
    }

    func testWindowsTarget() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                    TargetDescription(name: "exe", dependencies: ["lib"]),
                    TargetDescription(name: "lib", dependencies: []),
                ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .windows),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        let args = [
            "-target", "x86_64-unknown-windows-msvc", "-g", "-gcodeview", "-O0",
            "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks", "-I", "/Pkg/Sources/lib/include"
        ]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc", "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap", "-Xcc", "-I", "-Xcc", "/Pkg/Sources/lib/include", "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            "/fake/path/to/swiftc",
            "-L", "/path/to/build/debug", "-o", "/path/to/build/debug/exe.exe",
            "-module-name", "exe", "-emit-executable",
            "@/path/to/build/debug/exe.product/Objects.LinkFileList",
             "-target", "x86_64-unknown-windows-msvc",
            ])

        let executablePathExtension = try result.buildProduct(for: "exe").binary.extension
        XCTAssertMatch(executablePathExtension, "exe")
    }

    func testWASITarget() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/app/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h",
            "/Pkg/Tests/test/TestCase.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "app", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "test", dependencies: ["lib"], type: .test)
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var parameters = mockBuildParameters(destinationTriple: .wasi)
        parameters.shouldLinkStaticSwiftStdlib = true
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(4)

        let lib = try result.target(for: "lib").clangTarget()
        let args = [
            "-target", "wasm32-unknown-wasi", "-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1",
            "-fblocks", "-fmodules", "-fmodule-name=lib", "-I", "/Pkg/Sources/lib/include",
            "-fmodules-cache-path=/path/to/build/debug/ModuleCache"
        ]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(lib.objects, [AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")])
        XCTAssertEqual(lib.moduleMap, AbsolutePath("/path/to/build/debug/lib.build/module.modulemap"))

        let exe = try result.target(for: "app").swiftTarget().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g",
                .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc",
                "-fmodule-map-file=/path/to/build/debug/lib.build/module.modulemap",
                "-Xcc", "-I", "-Xcc", "/Pkg/Sources/lib/include",
                "-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence
            ]
        )

        let appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
                "-o", "/path/to/build/debug/app.wasm",
                 "-module-name", "app", "-static-stdlib", "-emit-executable",
                 "@/path/to/build/debug/app.product/Objects.LinkFileList",
                 "-target", "wasm32-unknown-wasi"
            ]
        )

        let executablePathExtension = appBuildDescription.binary.extension
        XCTAssertEqual(executablePathExtension, "wasm")

        let testBuildDescription = try result.buildProduct(for: "PkgPackageTests")
        XCTAssertEqual(
            try testBuildDescription.linkArguments(),
            [
                "/fake/path/to/swiftc", "-L", "/path/to/build/debug",
                "-o", "/path/to/build/debug/PkgPackageTests.wasm",
                "-module-name", "PkgPackageTests", "-emit-executable",
                "@/path/to/build/debug/PkgPackageTests.product/Objects.LinkFileList",
                "-target", "wasm32-unknown-wasi"
            ]
        )

        let testPathExtension = testBuildDescription.binary.extension
        XCTAssertEqual(testPathExtension, "wasm")
    }

    func testEntrypointRenaming() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    toolsVersion: .v5_5,
                    targets: [
                        TargetDescription(name: "exe", type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        func createResult(for triple: TSCUtility.Triple) throws -> BuildPlanResult {
            try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(canRenameEntrypointFunctionName: true, destinationTriple: triple),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }
        let supportingTriples: [TSCUtility.Triple] = [.x86_64Linux, .macOS]
        for triple in supportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "exe_main"])
            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.contains("exe_main")])
        }

        let unsupportingTriples: [TSCUtility.Triple] = [.wasi, .windows]
        for triple in unsupportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertNoMatch(exe, ["-entry-point-function-name"])
        }
    }

    func testIndexStore() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func check(for mode: BuildParameters.IndexStoreMode, config: BuildConfiguration) throws {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(config: config, indexStoreMode: mode),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let lib = try result.target(for: "lib").clangTarget()
            let path = StringPattern.equal(result.plan.buildParameters.indexStore.pathString)

            #if os(macOS)
            XCTAssertMatch(try lib.basicArguments(isCXX: false), [.anySequence, "-index-store-path", path, .anySequence])
            #else
            XCTAssertNoMatch(try lib.basicArguments(isCXX: false), [.anySequence, "-index-store-path", path, .anySequence])
            #endif

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-index-store-path", path, .anySequence])
        }

        try check(for: .auto, config: .debug)
        try check(for: .on, config: .debug)
        try check(for: .on, config: .release)
    }

    func testPlatforms() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "B",
                    path: .init("/B"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.12"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        let aTarget = try result.target(for: "ATarget").swiftTarget().compileArguments()
      #if os(macOS)
        XCTAssertMatch(aTarget, [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.13")), .anySequence])
      #else
        XCTAssertMatch(aTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence] )
      #endif

        let bTarget = try result.target(for: "BTarget").swiftTarget().compileArguments()
      #if os(macOS)
        XCTAssertMatch(bTarget, [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.12")), .anySequence])
      #else
        XCTAssertMatch(bTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence] )
      #endif
    }

    func testPlatformsValidation() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "A",
                    path: .init("/A"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                        PlatformDescription(name: "ios", version: "10"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "B",
                    path: .init("/B"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14"),
                        PlatformDescription(name: "ios", version: "11"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(Diagnostics.fatalError) {
            _ = try BuildPlan(
                buildParameters: mockBuildParameters(destinationTriple: .macOS),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
        }

        testDiagnostics(observability.diagnostics) { result in
            let diagnosticMessage = """
            the library 'ATarget' requires macos 10.13, but depends on the product 'BLibrary' which requires macos 10.14; \
            consider changing the library 'ATarget' to require macos 10.14 or later, or the product 'BLibrary' to require \
            macos 10.13 or earlier.
            """
            result.check(diagnostic: .contains(diagnosticMessage), severity: .error)
        }
    }

    func testBuildSettings() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/A/Sources/exe/main.swift",
            "/A/Sources/bar/bar.swift",
            "/A/Sources/cbar/barcpp.cpp",
            "/A/Sources/cbar/bar.c",
            "/A/Sources/cbar/include/bar.h",

            "/B/Sources/t1/dep.swift",
            "/B/Sources/t2/dep.swift",
            "<end>"
        )

        let aManifest = Manifest.createRootManifest(
            name: "A",
            path: .init("/A"),
            toolsVersion: .v5,
            dependencies: [
                .localSourceControl(path: .init("/B"), requirement: .upToNextMajor(from: "1.0.0")),
            ],
            targets: [
                try TargetDescription(
                    name: "cbar",
                    settings: [
                        .init(tool: .c, kind: .headerSearchPath("Sources/headers")),
                        .init(tool: .cxx, kind: .headerSearchPath("Sources/cppheaders")),
                        .init(tool: .c, kind: .define("CCC=2")),
                        .init(tool: .cxx, kind: .define("RCXX"), condition: .init(config: "release")),
                        .init(tool: .linker, kind: .linkedFramework("best")),
                        .init(tool: .c, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                        .init(tool: .cxx, kind: .unsafeFlags(["-Icxxfoo", "-L", "cxxbar"])),
                    ]
                ),
                try TargetDescription(
                    name: "bar", dependencies: ["cbar", "Dep"],
                    settings: [
                        .init(tool: .swift, kind: .define("LINUX"), condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, kind: .define("RLINUX"), condition: .init(platformNames: ["linux"], config: "release")),
                        .init(tool: .swift, kind: .define("DMACOS"), condition: .init(platformNames: ["macos"], config: "debug")),
                        .init(tool: .swift, kind: .unsafeFlags(["-Isfoo", "-L", "sbar"])),
                    ]
                ),
                try TargetDescription(
                    name: "exe", dependencies: ["bar"],
                    settings: [
                        .init(tool: .swift, kind: .define("FOO")),
                        .init(tool: .linker, kind: .linkedLibrary("sqlite3")),
                        .init(tool: .linker, kind: .linkedFramework("CoreData"), condition: .init(platformNames: ["macos"])),
                        .init(tool: .linker, kind: .unsafeFlags(["-Ilfoo", "-L", "lbar"])),
                    ]
                ),
            ]
        )

        let bManifest = Manifest.createFileSystemManifest(
            name: "B",
            path: .init("/B"),
            toolsVersion: .v5,
            products: [
                try ProductDescription(name: "Dep", type: .library(.automatic), targets: ["t1", "t2"]),
            ],
            targets: [
                try TargetDescription(
                    name: "t1",
                    settings: [
                        .init(tool: .swift, kind: .define("DEP")),
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
                try TargetDescription(
                    name: "t2",
                    settings: [
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
            ])

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [aManifest, bManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func createResult(for dest: TSCUtility.Triple) throws -> BuildPlanResult {
            return try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(destinationTriple: dest),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }

        do {
            let result = try createResult(for: .x86_64Linux)

            let dep = try result.target(for: "t1").swiftTarget().compileArguments()
            XCTAssertMatch(dep, [.anySequence, "-DDEP", .end])

            let cbar = try result.target(for: "cbar").clangTarget().basicArguments(isCXX: false)
            XCTAssertMatch(cbar, [.anySequence, "-DCCC=2", "-I/A/Sources/cbar/Sources/headers", "-I/A/Sources/cbar/Sources/cppheaders", "-Icfoo", "-L", "cbar", "-Icxxfoo", "-L", "cxxbar", .end])

            let bar = try result.target(for: "bar").swiftTarget().compileArguments()
            XCTAssertMatch(bar, [.anySequence, "-DLINUX", "-Isfoo", "-L", "sbar", .end])

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-DFOO", .end])

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.anySequence, "-lsqlite3", "-llibz", "-framework", "best", "-Ilfoo", "-L", "lbar", .end])
        }

        do {
            let result = try createResult(for: .macOS)

            let cbar = try result.target(for: "cbar").clangTarget().basicArguments(isCXX: false)
            XCTAssertMatch(cbar, [.anySequence, "-DCCC=2", "-I/A/Sources/cbar/Sources/headers", "-I/A/Sources/cbar/Sources/cppheaders", "-Icfoo", "-L", "cbar", "-Icxxfoo", "-L", "cxxbar", .end])

            let bar = try result.target(for: "bar").swiftTarget().compileArguments()
            XCTAssertMatch(bar, [.anySequence, "-DDMACOS", "-Isfoo", "-L", "sbar", .end])

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-DFOO", .end])

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.anySequence, "-lsqlite3", "-llibz", "-framework", "CoreData", "-framework", "best", "-Ilfoo", "-L", "lbar", .anySequence])
        }
    }

    func testExtraBuildFlags() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/A/Sources/exe/main.swift",
            "/fake/path/lib/libSomething.dylib",
            "<end>"
        )

        let aManifest = Manifest.createRootManifest(
            name: "A",
            path: .init("/A"),
            toolsVersion: .v5,
            targets: [
                try TargetDescription(name: "exe", dependencies: []),
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [aManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var flags = BuildFlags()
        flags.linkerFlags = ["-L", "/path/to/foo", "-L/path/to/foo", "-rpath=foo", "-rpath", "foo"]
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(flags: flags),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let exe = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exe, [.anySequence, "-L", "/path/to/foo", "-L/path/to/foo", "-Xlinker", "-rpath=foo", "-Xlinker", "-rpath", "-Xlinker", "foo", "-L", "/fake/path/lib"])
    }

    func testUserToolchainCompileFlags() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let userDestination = Destination(sdk: AbsolutePath("/fake/sdk"),
            binDir: UserToolchain.default.destination.binDir,
            extraCCFlags: ["-I/fake/sdk/sysroot", "-clang-flag-from-json"],
            extraSwiftCFlags: ["-swift-flag-from-json"])
        let mockToolchain = try UserToolchain(destination: userDestination)
        let extraBuildParameters = mockBuildParameters(toolchain: mockToolchain,
            flags: BuildFlags(xcc: ["-clang-command-line-flag"], xswiftc: ["-swift-command-line-flag"]))
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: extraBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        var args: [StringPattern] = []
      #if os(macOS)
        args += ["-isysroot"]
      #else
        args += ["--sysroot"]
      #endif
        args += ["/fake/sdk", "-I/fake/sdk/sysroot", "-clang-flag-from-json", "-clang-command-line-flag"]
        XCTAssertMatch(try lib.basicArguments(isCXX: false), args)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-module-cache-path", "/path/to/build/debug/ModuleCache", .anySequence, "-swift-flag-from-json", "-Xcc", "-clang-command-line-flag", "-swift-command-line-flag"])
    }

    func testExecBuildTimeDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/exe/main.swift",
            "/PkgA/Sources/swiftlib/lib.swift",
            "/PkgB/Sources/PkgB/PkgB.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    products: [
                        ProductDescription(name: "swiftlib", type: .library(.automatic), targets: ["swiftlib"]),
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"])
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                        TargetDescription(name: "swiftlib", dependencies: ["exe"]),
                    ]),
                Manifest.createRootManifest(
                    name: "PkgB",
                    path: .init("/PkgB"),
                    dependencies: [
                        .localSourceControl(path: .init("/PkgA"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "PkgB", dependencies: ["swiftlib"]),
                    ]),
            ],
            explicitProduct: "exe",
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
                inputs: ["/PkgA/Sources/swiftlib/lib.swift","/path/to/build/debug/exe"]
                outputs: ["/path/to/build/debug/swiftlib.build/lib.swift.o","/path/to/build/debug/
            """))
    }

    func testObjCHeader1() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Bar/main.m",
            "/PkgA/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
        #if os(macOS)
          XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
        #else
          XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
        #endif

        let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
        #if os(macOS)
          XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
        #else
          XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
        #endif

        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
              "/path/to/build/debug/Bar.build/main.m.o":
                tool: clang
                inputs: ["/path/to/build/debug/Foo.swiftmodule","/PkgA/Sources/Bar/main.m"]
                outputs: ["/path/to/build/debug/Bar.build/main.m.o"]
                description: "Compiling Bar main.m"
            """))
    }

    func testObjCHeader2() throws {
        // This has a Swift and ObjC target in different packages with automatic product type.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Bar/main.m",
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    dependencies: [
                        .localSourceControl(path: .init("/PkgB"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "PkgB",
                    path: .init("/PkgB"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

         let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
         #if os(macOS)
           XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #else
           XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #endif

         let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
         #if os(macOS)
           XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #else
           XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #endif

        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
               "/path/to/build/debug/Bar.build/main.m.o":
                 tool: clang
                 inputs: ["/path/to/build/debug/Foo.swiftmodule","/PkgA/Sources/Bar/main.m"]
                 outputs: ["/path/to/build/debug/Bar.build/main.m.o"]
                 description: "Compiling Bar main.m"
             """))
    }

    func testObjCHeader3() throws {
        // This has a Swift and ObjC target in different packages with dynamic product type.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Bar/main.m",
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    dependencies: [
                        .localSourceControl(path: .init("/PkgB"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
                Manifest.createFileSystemManifest(
                    name: "PkgB",
                    path: .init("/PkgB"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.dynamic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let dynamicLibraryExtension = plan.buildParameters.triple.dynamicLibraryExtension
        let result = try BuildPlanResult(plan: plan)

         let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
         #if os(macOS)
           XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #else
           XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #endif

         let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
         #if os(macOS)
           XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #else
           XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #endif

        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
               "/path/to/build/debug/Bar.build/main.m.o":
                 tool: clang
                 inputs: ["/path/to/build/debug/libFoo\(dynamicLibraryExtension)","/PkgA/Sources/Bar/main.m"]
                 outputs: ["/path/to/build/debug/Bar.build/main.m.o"]
                 description: "Compiling Bar main.m"
             """))
    }

    func testModulewrap() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .x86_64Linux),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let objects = try result.buildProduct(for: "exe").objects
        XCTAssertTrue(objects.contains(AbsolutePath("/path/to/build/debug/exe.build/exe.swiftmodule.o")), objects.description)
        XCTAssertTrue(objects.contains(AbsolutePath("/path/to/build/debug/lib.build/lib.swiftmodule.o")), objects.description)

        let yaml = fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(result.plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
              "/path/to/build/debug/exe.build/exe.swiftmodule.o":
                tool: shell
                inputs: ["/path/to/build/debug/exe.build/exe.swiftmodule"]
                outputs: ["/path/to/build/debug/exe.build/exe.swiftmodule.o"]
                description: "Wrapping AST for exe for debugging"
                args: ["/fake/path/to/swiftc","-modulewrap","/path/to/build/debug/exe.build/exe.swiftmodule","-o","/path/to/build/debug/exe.build/exe.swiftmodule.o","-target","x86_64-unknown-linux-gnu"]
            """))
        XCTAssertMatch(contents, .contains("""
              "/path/to/build/debug/lib.build/lib.swiftmodule.o":
                tool: shell
                inputs: ["/path/to/build/debug/lib.swiftmodule"]
                outputs: ["/path/to/build/debug/lib.build/lib.swiftmodule.o"]
                description: "Wrapping AST for lib for debugging"
                args: ["/fake/path/to/swiftc","-modulewrap","/path/to/build/debug/lib.swiftmodule","-o","/path/to/build/debug/lib.build/lib.swiftmodule.o","-target","x86_64-unknown-linux-gnu"]
            """))
    }

    func testSwiftBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(rule: .copy, path: "foo.txt"),
                                .init(rule: .process(localization: .none), path: "bar.txt"),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar"
                        ),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let fooTarget = try result.target(for: "Foo").swiftTarget()
        XCTAssertEqual(fooTarget.objects.map{ $0.pathString }, [
            "/path/to/build/debug/Foo.build/Foo.swift.o",
            "/path/to/build/debug/Foo.build/resource_bundle_accessor.swift.o"
        ])

        let resourceAccessor = fooTarget.sources.first{ $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and https://github.com/apple/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = Bundle.main."))

        let barTarget = try result.target(for: "Bar").swiftTarget()
        XCTAssertEqual(barTarget.objects.map{ $0.pathString }, [
            "/path/to/build/debug/Bar.build/Bar.swift.o",
        ])
    }

    func testSwiftWASIBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "PkgA",
                    path: .init("/PkgA"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(rule: .copy, path: "foo.txt"),
                                .init(rule: .process(localization: .none), path: "bar.txt"),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar"
                        ),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .wasi),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let fooTarget = try result.target(for: "Foo").swiftTarget()
        XCTAssertEqual(fooTarget.objects.map{ $0.pathString }, [
            "/path/to/build/debug/Foo.build/Foo.swift.o",
            "/path/to/build/debug/Foo.build/resource_bundle_accessor.swift.o"
        ])

        let resourceAccessor = fooTarget.sources.first{ $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and https://github.com/apple/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = \""))

        let barTarget = try result.target(for: "Bar").swiftTarget()
        XCTAssertEqual(barTarget.objects.map{ $0.pathString }, [
            "/path/to/build/debug/Bar.build/Bar.swift.o",
        ])
    }

    func testShouldLinkStaticSwiftStdlib() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        let supportingTriples: [TSCUtility.Triple] = [.x86_64Linux, .arm64Linux, .wasi]
        for triple in supportingTriples {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true, destinationTriple: triple),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, ["-static-stdlib"])
            let lib = try result.target(for: "lib").swiftTarget().compileArguments()
            XCTAssertMatch(lib, ["-static-stdlib"])
            let link = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(link, ["-static-stdlib"])
        }
    }

    func testXCFrameworkBinaryTargets(platform: String, arch: String, destinationTriple: TSCUtility.Triple) throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/Library/Library.swift",
            "/Pkg/Sources/CLibrary/library.c",
            "/Pkg/Sources/CLibrary/include/library.h"
        )

        try! fs.createDirectory(AbsolutePath("/Pkg/Framework.xcframework"), recursive: true)
        try! fs.writeFileContents(
            AbsolutePath("/Pkg/Framework.xcframework/Info.plist"),
            bytes: ByteString(encodingAsUTF8: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>AvailableLibraries</key>
                    <array>
                        <dict>
                            <key>LibraryIdentifier</key>
                            <string>\(platform)-\(arch)</string>
                            <key>LibraryPath</key>
                            <string>Framework.framework</string>
                            <key>SupportedArchitectures</key>
                            <array>
                                <string>\(arch)</string>
                            </array>
                            <key>SupportedPlatform</key>
                            <string>\(platform)</string>
                        </dict>
                    </array>
                    <key>CFBundlePackageType</key>
                    <string>XFWK</string>
                    <key>XCFrameworkFormatVersion</key>
                    <string>1.0</string>
                </dict>
                </plist>
                """))

        try! fs.createDirectory(AbsolutePath("/Pkg/StaticLibrary.xcframework"), recursive: true)
        try! fs.writeFileContents(
            AbsolutePath("/Pkg/StaticLibrary.xcframework/Info.plist"),
            bytes: ByteString(encodingAsUTF8: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>AvailableLibraries</key>
                    <array>
                        <dict>
                            <key>LibraryIdentifier</key>
                            <string>\(platform)-\(arch)</string>
                            <key>HeadersPath</key>
                            <string>Headers</string>
                            <key>LibraryPath</key>
                            <string>libStaticLibrary.a</string>
                            <key>SupportedArchitectures</key>
                            <array>
                                <string>\(arch)</string>
                            </array>
                            <key>SupportedPlatform</key>
                            <string>\(platform)</string>
                        </dict>
                    </array>
                    <key>CFBundlePackageType</key>
                    <string>XFWK</string>
                    <key>XCFrameworkFormatVersion</key>
                    <string>1.0</string>
                </dict>
                </plist>
                """))

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    products: [
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                        ProductDescription(name: "Library", type: .library(.dynamic), targets: ["Library"]),
                        ProductDescription(name: "CLibrary", type: .library(.dynamic), targets: ["CLibrary"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["Library"]),
                        TargetDescription(name: "Library", dependencies: ["Framework"]),
                        TargetDescription(name: "CLibrary", dependencies: ["StaticLibrary"]),
                        TargetDescription(name: "Framework", path: "Framework.xcframework", type: .binary),
                        TargetDescription(name: "StaticLibrary", path: "StaticLibrary.xcframework", type: .binary),
                    ]
                ),
            ],
            binaryArtifacts: [
                .init(kind: .xcframework, originURL: nil, path: AbsolutePath("/Pkg/Framework.xcframework")),
                .init(kind: .xcframework, originURL: nil, path: AbsolutePath("/Pkg/StaticLibrary.xcframework"))
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: destinationTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        XCTAssertNoDiagnostics(observability.diagnostics)

        result.checkProductsCount(3)
        result.checkTargetsCount(3)

        let libraryBasicArguments = try result.target(for: "Library").swiftTarget().compileArguments()
        XCTAssertMatch(libraryBasicArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])

        let libraryLinkArguments = try result.buildProduct(for: "Library").linkArguments()
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-L", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let exeCompileArguments = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exeCompileArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])

        let exeLinkArguments = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-L", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let clibraryBasicArguments = try result.target(for: "CLibrary").clangTarget().basicArguments(isCXX: false)
        XCTAssertMatch(clibraryBasicArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(clibraryBasicArguments, [.anySequence, "-I", "/Pkg/StaticLibrary.xcframework/\(platform)-\(arch)/Headers", .anySequence])

        let clibraryLinkArguments = try result.buildProduct(for: "CLibrary").linkArguments()
        XCTAssertMatch(clibraryLinkArguments, [.anySequence, "-F", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(clibraryLinkArguments, [.anySequence, "-L", "/path/to/build/debug", .anySequence])
        XCTAssertMatch(clibraryLinkArguments, ["-lStaticLibrary"])

        let executablePathExtension = try result.buildProduct(for: "exe").binary.extension ?? ""
        XCTAssertMatch(executablePathExtension, "")

        let dynamicLibraryPathExtension = try result.buildProduct(for: "Library").binary.extension
        XCTAssertMatch(dynamicLibraryPathExtension, "dylib")
    }

    func testXCFrameworkBinaryTargets() throws {
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "x86_64", destinationTriple: .macOS)

        let arm64Triple = try TSCUtility.Triple("arm64-apple-macosx")
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64", destinationTriple: arm64Triple)

        let arm64eTriple = try TSCUtility.Triple("arm64e-apple-macosx")
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64e", destinationTriple: arm64eTriple)
    }

    func testArtifactsArchiveBinaryTargets(artifactTriples:[TSCUtility.Triple], destinationTriple: TSCUtility.Triple) throws -> Bool {
        let fs = InMemoryFileSystem(emptyFiles: "/Pkg/Sources/exe/main.swift")

        let artifactName = "my-tool"
        let toolPath = AbsolutePath("/Pkg/MyTool.artifactbundle")
        try fs.createDirectory(toolPath, recursive: true)

        try fs.writeFileContents(
            toolPath.appending(component: "info.json"),
            bytes: ByteString(encodingAsUTF8: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "\(artifactName)": {
                            "type": "executable",
                            "version": "1.1.0",
                            "variants": [
                                {
                                    "path": "all-platforms/mytool",
                                    "supportedTriples": ["\(artifactTriples.map{ $0.tripleString }.joined(separator: "\", \""))"]
                                }
                            ]
                        }
                    }
                }
        """))

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    products: [
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["MyTool"]),
                        TargetDescription(name: "MyTool", path: "MyTool.artifactbundle", type: .binary),
                    ]
                ),
            ],
            binaryArtifacts: [
                .init(kind: .artifactsArchive, originURL: nil, path: toolPath),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: destinationTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        XCTAssertNoDiagnostics(observability.diagnostics)

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let availableTools = try result.buildProduct(for: "exe").availableTools
        return availableTools.contains(where: { $0.key == artifactName })
    }

    func testArtifactsArchiveBinaryTargets() throws {
        XCTAssertTrue(try testArtifactsArchiveBinaryTargets(artifactTriples: [.macOS], destinationTriple: .macOS))

        do {
            let triples = try ["arm64-apple-macosx",  "x86_64-apple-macosx", "x86_64-unknown-linux-gnu"].map(TSCUtility.Triple.init)
            XCTAssertTrue(try testArtifactsArchiveBinaryTargets(artifactTriples: triples, destinationTriple: triples.first!))
        }

        do {
            let triples = try ["x86_64-unknown-linux-gnu"].map(TSCUtility.Triple.init)
            XCTAssertFalse(try testArtifactsArchiveBinaryTargets(artifactTriples: triples, destinationTriple: .macOS))
        }
    }

    func testAddressSanitizer() throws {
        try sanitizerTest(.address, expectedName: "address")
    }

    func testThreadSanitizer() throws {
        try sanitizerTest(.thread, expectedName: "thread")
    }

    func testUndefinedSanitizer() throws {
        try sanitizerTest(.undefined, expectedName: "undefined")
    }

    func testScudoSanitizer() throws {
        try sanitizerTest(.scudo, expectedName: "scudo")
    }

    private func sanitizerTest(_ sanitizer: SPMBuildCore.Sanitizer, expectedName: String) throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Sources/clib/clib.c",
            "/Pkg/Sources/clib/include/clib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fs,
            manifests: [
                Manifest.createRootManifest(
                    name: "Pkg",
                    path: .init("/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib", "clib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "clib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        // Unrealistic: we can't enable all of these at once on all platforms.
        // This test codifies current behavior, not ideal behavior, and
        // may need to be amended if we change it.
        var parameters = mockBuildParameters(shouldLinkStaticSwiftStdlib: true)
        parameters.sanitizers = EnabledSanitizers([sanitizer])

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-sanitize=\(expectedName)"])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-sanitize=\(expectedName)"])

        let clib  = try result.target(for: "clib").clangTarget().basicArguments(isCXX: false)
        XCTAssertMatch(clib, ["-fsanitize=\(expectedName)"])

        XCTAssertMatch(try result.buildProduct(for: "exe").linkArguments(), ["-sanitize=\(expectedName)"])
    }
}

// MARK:- Test Helpers

private enum Error: Swift.Error {
    case error(String)
}

private struct BuildPlanResult {

    let plan: BuildPlan
    let targetMap: [String: TargetBuildDescription]
    let productMap: [String: ProductBuildDescription]

    init(plan: BuildPlan) throws {
        self.plan = plan
        self.productMap = try Dictionary(throwingUniqueKeysWithValues: plan.buildProducts.map{ ($0.product.name, $0) })
        self.targetMap = try Dictionary(throwingUniqueKeysWithValues: plan.targetMap.map{ ($0.0.name, $0.1) })
    }

    func checkTargetsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.targetMap.count, count, file: file, line: line)
    }

    func checkProductsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(plan.productMap.count, count, file: file, line: line)
    }

    func target(for name: String) throws -> TargetBuildDescription {
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

fileprivate extension TargetBuildDescription {
    func swiftTarget() throws -> SwiftTargetBuildDescription {
        switch self {
        case .swift(let target):
            return target
        default:
            throw Error.error("Unexpected \(self) type found")
        }
    }

    func clangTarget() throws -> ClangTargetBuildDescription {
        switch self {
        case .clang(let target):
            return target
        default:
            throw Error.error("Unexpected \(self) type")
        }
    }
}

fileprivate extension TSCUtility.Triple {
    static let x86_64Linux = try! Triple("x86_64-unknown-linux-gnu")
    static let arm64Linux = try! Triple("aarch64-unknown-linux-gnu")
    static let arm64Android = try! Triple("aarch64-unknown-linux-android")
    static let windows = try! Triple("x86_64-unknown-windows-msvc")
    static let wasi = try! Triple("wasm32-unknown-wasi")
}
