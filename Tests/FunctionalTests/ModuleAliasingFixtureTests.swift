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

    func testModuleRenaming() throws {
        #if swift(<5.6)
        try XCTSkipIf(true, "Module aliasing is only supported on swift 5.6+")
        #endif

        try fixture(name: "Miscellaneous/ModuleAliasing/DirectDeps") { fixturePath in
            let app = fixturePath.appending(components: "AppPkg")
            XCTAssertBuilds(app, extraArgs: ["--vv"])
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "App"))
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "App"))
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "GameUtils.swiftmodule"))
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "GameUtils.swiftmodule"))
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Utils.swiftmodule"))
            XCTAssertFileExists(fixturePath.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "Utils.swiftmodule"))
            
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: app)
            let output = try result.utf8Output() + result.utf8stderrOutput()
           
            // FIXME: rdar://88722540
            // The process from above crashes in a certain env, so print
            // the output for further investigation
            try XCTSkipIf(result.exitStatus != .terminated(code: 0), "Skipping due to an expected failure being investigated in rdar://88722540\nResult: \(result.exitStatus)\nOutput: \(output)")
        }
    }
}
