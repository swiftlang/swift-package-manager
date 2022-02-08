/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Commands
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest
 
class ModuleAliasingTests: XCTestCase {

    func testExternalSimple() {
        fixture(name: "Miscellaneous/ModuleAliasing/Simple") { prefix in
            let app = prefix.appending(components: "AppPkg")
            XCTAssertBuilds(app)
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "App"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "App"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "GameUtils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "GameUtils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Utils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "Utils.swiftmodule"))
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: app)
            XCTAssertEqual(result.exitStatus, .terminated(code: 0))
        }
    }
}
