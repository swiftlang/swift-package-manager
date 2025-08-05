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
import _InternalTestSupport
import Workspace
import XCTest
 
final class ModuleAliasingFixtureTests: XCTestCase {
    func testModuleDirectDeps1() async throws {
        try await fixtureXCTest(name: "ModuleAliasing/DirectDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            await XCTAssertBuilds(
                pkgPath,
                extraArgs: ["--vv"],
                buildSystem: .native,
            )
            XCTAssertFileExists(buildPath.appending(components: executableName("App")))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "GameUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "Utils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                buildSystem: .native,
            )
        }
    }

    func testModuleDirectDeps2() async throws {
        try await fixtureXCTest(name: "ModuleAliasing/DirectDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            await XCTAssertBuilds(
                pkgPath,
                extraArgs: ["--vv"],
                buildSystem: .native,
            )
            XCTAssertFileExists(buildPath.appending(components: executableName("App")))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "AUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "BUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                buildSystem: .native,
            )
        }
    }

    func testModuleNestedDeps1() async throws {
        try await fixtureXCTest(name: "ModuleAliasing/NestedDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            await XCTAssertBuilds(
                pkgPath,
                extraArgs: ["--vv"],
                buildSystem: .native,
            )
            XCTAssertFileExists(buildPath.appending(components: executableName("App")))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "A.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "AFooUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "CarUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "X.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "XFooUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "XUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                buildSystem: .native,
            )
        }
    }

    func testModuleNestedDeps2() async throws {
        try await fixtureXCTest(name: "ModuleAliasing/NestedDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            await XCTAssertBuilds(
                pkgPath,
                extraArgs: ["--vv"],
                buildSystem: .native,
            )
            XCTAssertFileExists(buildPath.appending(components: executableName("App")))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "A.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "BUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "CUtils.swiftmodule"))
            XCTAssertFileExists(buildPath.appending(components: "Modules", "XUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                buildSystem: .native,
            )
        }
    }
}
