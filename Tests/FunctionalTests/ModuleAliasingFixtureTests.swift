//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Commands
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest
 
class ModuleAliasingFixtureTests: XCTestCase {

    func testModuleDirectDeps1() throws {
        #if swift(<5.7)
        try XCTSkipIf(true, "Module aliasing is only supported on swift 5.7+")
        #endif

        try fixture(name: "ModuleAliasing/DirectDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertBuilds(pkgPath, extraArgs: ["--vv"])
            XCTAssertFileExists(buildPath.appending(components: "App"))
            XCTAssertFileExists(buildPath.appending(components: "GameUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Utils.swiftmodule"))
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: pkgPath)
            let output = try result.utf8Output() + result.utf8stderrOutput()
            XCTAssertEqual(result.exitStatus, .terminated(code: 0), "output: \(output)")
        }
    }

    func testModuleDirectDeps2() throws {
        #if swift(<5.7)
        try XCTSkipIf(true, "Module aliasing is only supported on swift 5.7+")
        #endif

        try fixture(name: "ModuleAliasing/DirectDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertBuilds(pkgPath, extraArgs: ["--vv"])
            XCTAssertFileExists(buildPath.appending(components: "App"))
            XCTAssertFileExists(buildPath.appending(components: "AUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "BUtils.swiftmodule"))
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: pkgPath)
            let output = try result.utf8Output() + result.utf8stderrOutput()
            XCTAssertEqual(result.exitStatus, .terminated(code: 0), "output: \(output)")
        }
    }
}
