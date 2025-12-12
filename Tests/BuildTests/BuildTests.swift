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

import _InternalTestSupport
@testable import DriverSupport
import SPMBuildCore
import PackageModel
import TSCBasic
import XCTest

class BuildTests: BuildSystemProviderTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(type(of: self) == BuildTests.self, "Skipping this test since it will be run in subclasses that will provide different build systems to test.")
    }

    func testPackageNameFlag() async throws {
        try XCTSkipIfPlatformCI() // test is disabled because it isn't stable, see rdar://118239206
        try XCTSkipOnWindows(because: "https://github.com/swiftlang/swift-package-manager/issues/8547: 'swift test' was stalled.")
        let isFlagSupportedInDriver = try DriverSupport.checkToolchainDriverFlags(
            flags: ["package-name"],
            toolchain: UserToolchain.default,
            fileSystem: localFileSystem
        )
        try await fixtureXCTest(name: "Miscellaneous/PackageNameFlag") { fixturePath in
            let (stdout, stderr) = try await executeSwiftBuild(
                fixturePath.appending("appPkg"),
                extraArgs: ["--vv"],
                buildSystem: buildSystemProvider
            )

            let out = if buildSystemProvider == .swiftbuild {
                stderr
            } else {
                stdout
            }

            XCTAssertMatch(out, .contains("-module-name Foo"))
            XCTAssertMatch(out, .contains("-module-name Zoo"))
            XCTAssertMatch(out, .contains("-module-name Bar"))
            XCTAssertMatch(out, .contains("-module-name Baz"))
            XCTAssertMatch(out, .contains("-module-name App"))
            XCTAssertMatch(out, .contains("-module-name exe"))
            if isFlagSupportedInDriver {
                XCTAssertMatch(out, .contains("-package-name apppkg"))
                XCTAssertMatch(out, .contains("-package-name foopkg"))
                // the flag is not supported if tools-version < 5.9
                XCTAssertNoMatch(out, .contains("-package-name barpkg"))
            } else {
                XCTAssertNoMatch(out, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    func testTargetsWithPackageAccess() async throws {
        let isFlagSupportedInDriver = try DriverSupport.checkToolchainDriverFlags(
            flags: ["package-name"],
            toolchain: UserToolchain.default,
            fileSystem: localFileSystem
        )
        try await fixtureXCTest(name: "Miscellaneous/TargetPackageAccess") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("libPkg"),
                extraArgs: ["-v"],
                buildSystem: buildSystemProvider
            )
            if isFlagSupportedInDriver {
                let moduleFlag1 = stdout.range(of: "-module-name DataModel")
                XCTAssertNotNil(moduleFlag1)
                let stdoutNext1 = stdout[moduleFlag1!.upperBound...]
                let packageFlag1 = stdoutNext1.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag1)

                let moduleFlag2 = stdoutNext1.range(of: "-module-name DataManager")
                XCTAssertNotNil(moduleFlag2)
                XCTAssertTrue(packageFlag1!.upperBound < moduleFlag2!.lowerBound)
                let stdoutNext2 = stdoutNext1[moduleFlag2!.upperBound...]
                let packageFlag2 = stdoutNext2.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag2)

                let moduleFlag3 = stdoutNext2.range(of: "-module-name Core")
                XCTAssertNotNil(moduleFlag3)
                XCTAssertTrue(packageFlag2!.upperBound < moduleFlag3!.lowerBound)
                let stdoutNext3 = stdoutNext2[moduleFlag3!.upperBound...]
                let packageFlag3 = stdoutNext3.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag3)

                let moduleFlag4 = stdoutNext3.range(of: "-module-name MainLib")
                XCTAssertNotNil(moduleFlag4)
                XCTAssertTrue(packageFlag3!.upperBound < moduleFlag4!.lowerBound)
                let stdoutNext4 = stdoutNext3[moduleFlag4!.upperBound...]
                let packageFlag4 = stdoutNext4.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag4)

                let moduleFlag5 = stdoutNext4.range(of: "-module-name ExampleApp")
                XCTAssertNotNil(moduleFlag5)
                XCTAssertTrue(packageFlag4!.upperBound < moduleFlag5!.lowerBound)
                let stdoutNext5 = stdoutNext4[moduleFlag5!.upperBound...]
                let packageFlag5 = stdoutNext5.range(of: "-package-name")
                XCTAssertNil(packageFlag5)
            } else {
                XCTAssertNoMatch(stdout, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }
}

class BuildTestsNative: BuildTests {
    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .native
    }
}

class BuildTestsSwiftBuild: BuildTests {
    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .swiftbuild
    }

    override func testTargetsWithPackageAccess() async throws {
        throw XCTSkip("Skip until swift build system can support this case.")
    }
}
