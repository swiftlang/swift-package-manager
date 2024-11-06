//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

import Basics
@testable import Build
import LLBuildManifest
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

final class WindowsBuildPlanTests: XCTestCase {
    // Tests that our build plan is build correctly to handle separation
    // of object files that export symbols and ones that don't and to ensure
    // DLL products pick up the right ones.

    func doTest(triple: Triple) async throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/libPkg/Sources/coreLib/coreLib.swift",
            "/libPkg/Sources/dllLib/dllLib.swift",
            "/libPkg/Sources/staticLib/staticLib.swift",
            "/libPkg/Sources/objectLib/objectLib.swift",
            "/exePkg/Sources/exe/main.swift",
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createFileSystemManifest(
                    displayName: "libPkg",
                    path: "/libPkg",
                    products: [
                        .init(name: "DLLProduct", type: .library(.dynamic), targets: ["dllLib"]),
                        .init(name: "StaticProduct", type: .library(.static), targets: ["staticLib"]),
                        .init(name: "ObjectProduct", type: .library(.automatic), targets: ["objectLib"]),
                    ],
                    targets: [
                        .init(name: "coreLib", dependencies: []),
                        .init(name: "dllLib", dependencies: ["coreLib"]),
                        .init(name: "staticLib", dependencies: ["coreLib"]),
                        .init(name: "objectLib", dependencies: ["coreLib"]),
                    ]
                ),
                .createRootManifest(
                    displayName: "exePkg",
                    path: "/exePkg",
                    dependencies: [.fileSystem(path: "/libPkg")],
                    targets: [
                        .init(name: "exe", dependencies: [
                            .product(name: "DLLProduct", package: "libPkg"),
                            .product(name: "StaticProduct", package: "libPkg"),
                            .product(name: "ObjectProduct", package: "libPkg"),
                        ]),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        let label: String
        let dylibPrefix: String
        let dylibExtension: String
        let dynamic: String
        switch triple {
        case Triple.x86_64Windows:
            label = "x86_64-unknown-windows-msvc"
            dylibPrefix = ""
            dylibExtension = "dll"
            dynamic = "/dynamic"
        case Triple.x86_64MacOS:
            label = "x86_64-apple-macosx"
            dylibPrefix = "lib"
            dylibExtension = "dylib"
            dynamic = ""
        case Triple.x86_64Linux:
            label = "x86_64-unknown-linux-gnu"
            dylibPrefix = "lib"
            dylibExtension = "so"
            dynamic = ""
        default:
            label = "fixme"
            dylibPrefix = ""
            dylibExtension = ""
            dynamic = ""
        }

        let tools: [String: [String]] = [
            "C.exe-\(label)-debug.exe": [
                "/path/to/build/\(label)/debug/coreLib.build/coreLib.swift.o",
                "/path/to/build/\(label)/debug/exe.build/main.swift.o",
                "/path/to/build/\(label)/debug/objectLib.build/objectLib.swift.o",
                "/path/to/build/\(label)/debug/staticLib.build/staticLib.swift.o",
                "/path/to/build/\(label)/debug/\(dylibPrefix)DLLProduct.\(dylibExtension)",
                "/path/to/build/\(label)/debug/exe.product/Objects.LinkFileList",
            ] + (triple.isMacOSX ? [] : [
                // modulewrap
                "/path/to/build/\(label)/debug/coreLib.build/coreLib.swiftmodule.o",
                "/path/to/build/\(label)/debug/exe.build/exe.swiftmodule.o",
                "/path/to/build/\(label)/debug/objectLib.build/objectLib.swiftmodule.o",
                "/path/to/build/\(label)/debug/staticLib.build/staticLib.swiftmodule.o",
            ]),
            "C.DLLProduct-\(label)-debug.dylib": [
                "/path/to/build/\(label)/debug/coreLib.build/coreLib.swift.o",
                "/path/to/build/\(label)/debug/dllLib.build\(dynamic)/dllLib.swift.o",
                "/path/to/build/\(label)/debug/DLLProduct.product/Objects.LinkFileList",
            ] + (triple.isMacOSX ? [] : [
                "/path/to/build/\(label)/debug/coreLib.build/coreLib.swiftmodule.o",
                "/path/to/build/\(label)/debug/dllLib.build/dllLib.swiftmodule.o",
            ])
        ]

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                triple: triple
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                triple: triple
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let llbuild = LLBuildManifestBuilder(
            plan,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        try llbuild.generateManifest(at: "/manifest")

        for (name, inputNames) in tools {
            let command = try XCTUnwrap(llbuild.manifest.commands[name])
            XCTAssertEqual(Set(command.tool.inputs), Set(inputNames.map({ Node.file(.init($0)) })))
        }
    }

    func testWindows() async throws {
        try await doTest(triple: .x86_64Windows)
    }

    // Make sure we didn't mess up macOS
    func testMacOS() async throws {
        try await doTest(triple: .x86_64MacOS)
    }

    // Make sure we didn't mess up linux
    func testLinux() async throws {
        try await doTest(triple: .x86_64Linux)
    }
}
