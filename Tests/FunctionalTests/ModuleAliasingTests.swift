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

    func testExternalSimple() throws {
        #if swift(<5.6)
        try XCTSkipIf(true, "Module aliasing is only supported on swift 5.6+")
        #endif
        
        fixture(name: "Miscellaneous/ModuleAliasing/DirectDeps") { prefix in
            let app = prefix.appending(components: "AppPkg")
            XCTAssertBuilds(app)
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "App"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "App"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "GameUtils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "GameUtils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "Utils.swiftmodule"))
            XCTAssertFileExists(prefix.appending(components: "AppPkg", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "release", "Utils.swiftmodule"))
            
            let result = try SwiftPMProduct.SwiftBuild.executeProcess([], packagePath: app)
            let output = try result.utf8Output() + result.utf8stderrOutput()
            
            #if os(Linux)
            // FIXME: the process crashes on CentOS 7, so print the output for further investigation
            print(output)
            #else
            XCTAssertEqual(result.exitStatus, .terminated(code: 0), "output: \(output)")
            #endif
        }
    }
}
