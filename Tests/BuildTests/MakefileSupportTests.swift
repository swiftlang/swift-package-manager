/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
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
import PackageDescription4

final class MakefileSupportTests: XCTestCase {

    func testBasics() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/CCore/include/CCore.h",
            "/Pkg/Sources/CCore/include/module.modulemap",
            "/Pkg/Sources/CCore/foo.c",
            "/Pkg/Sources/CCore/bar.c",

            "/Pkg/Sources/Core/foo.swift",
            "/Pkg/Sources/Core/bar.swift",

            "/Pkg/Sources/Exec/exe.swift",
            "/Pkg/Sources/Exec/main.swift",

            "/Pkg/Tests/CoreTests/CoreTests.swift",
            "/Pkg/Tests/LinuxMain.swift"
        )

        let pkg = Package(
            name: "Pkg",
            targets: [
                .target(name: "CCore"),
                .target(name: "Core", dependencies: ["CCore"]),
                .target(name: "Exec", dependencies: ["Core"]),
                .testTarget(name: "CoreTests", dependencies: ["Core"]),
            ]
        )
        let diagnostics = DiagnosticsEngine()
        let graph = loadMockPackageGraph4(
            ["/Pkg": pkg], root: "/Pkg", diagnostics: diagnostics, in: fs)

        // Generate the Makefile.
        let generator = MakefileGenerator(graph, packageRoot: AbsolutePath("/Pkg"), fs: fs)
        let makeFilePath = AbsolutePath("/Pkg/swift-ci/Makefile")
        try generator.generateMakefile(at: makeFilePath)

        // Read the input file.
        let expectedFilePath = AbsolutePath(#file).appending(
                RelativePath("../MakefileFixtures/testBasics/Makefile.txt"))
        let expectedMakefileContents = try localFileSystem.readFileContents(expectedFilePath)

        XCTAssertEqual(try fs.readFileContents(makeFilePath), expectedMakefileContents)
        XCTAssertTrue(fs.exists(AbsolutePath("/Pkg/swift-ci/utils.py")))
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
