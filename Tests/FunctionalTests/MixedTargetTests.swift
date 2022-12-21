//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import SPMTestSupport

// TODO(ncooke3): Create a larger E2E test with a complex mixed target.
// TODO(ncooke3): Explore using non-module import of mixed package in Objc Context.
// TODO(ncooke3): Explore using different ways to import $(ModuleName)-Swift header.

// TODO(ncooke3): Add test for mixed target with no ObjC-compatible Swift API.

// MARK: - MixedTargetTests

final class MixedTargetTests: XCTestCase {

    // MARK: - Testing Mixed Targets

    func testMixedTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "BasicMixedTarget"]
            )
        }
    }

    func testMixedTargetWithResources() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "MixedTargetWithResources"]
            )
        }
    }

    func testMixedTargetWithCustomModuleMap() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithCustomModuleMap"]
            )
        }
    }

    func testMixedTargetWithCustomModuleMapAndResources() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithCustomModuleMapAndResources"],
                // Surface warning where custom umbrella header does not
                // include `resource_bundle_accessor.h` in `build` directory.
                Xswiftc: ["-warnings-as-errors"]
            )
        }
    }

    // TODO(ncooke3): Can you export a C++ type in a mixed Obj-C / Cxx project?
    func testMixedTargetWithCXX() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "MixedTargetWithCXX"]
            )
        }
    }

    func testMixedTargetWithCXXAndCustomModuleMap() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithCXXAndCustomModuleMap"]
            )
        }
    }

    func testMixedTargetWithC() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "MixedTargetWithC"]
            )
        }
    }

    func testMixedTargetWithNoPublicObjectiveCHeaders() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "MixedTargetWithNoPublicObjectiveCHeadersTests"]
            )

            XCTAssertBuildFails(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithNoPublicObjectiveCHeadersTests"],
                Xcc: ["EXPECT_FAILURE"]
            )
        }
    }

    func testNonPublicHeadersAreVisibleFromSwiftHalfOfMixedTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithNonPublicHeaders"]
            )
        }
    }

    func testNonPublicHeadersAreNotVisibleFromOutsideOfTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            // The test target tries to access non-public headers so the build
            // should fail.
            XCTAssertBuildFails(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithNonPublicHeadersTests"],
                // Without selectively enabling the tests with the below macro,
                // the intentional build failure will break other unit tests
                // since all targets in the package are build when running
                // `swift test`.
                Xswiftc: ["MIXED_TARGET_WITH_C_TESTS"]
            )
        }
    }

    func testMixedTargetWithCustomPaths() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithCustomPaths"]
            )
        }

    }

    func testMixedTargetBuildsInReleaseMode() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: [
                    "--target", "BasicMixedTarget",
                    "--configuration", "release"
                ]
            )
        }
    }

    func testStaticallyLinkedMixedTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--product", "StaticallyLinkedBasicMixedTarget"]
            )
        }
    }

    func testDynamicallyLinkedMixedTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--product", "DynamicallyLinkedBasicMixedTarget"]
            )
        }
    }

    func testMixedTargetsPublicHeadersAreIncludedInHeaderSearchPathsForObjcSource() throws {
        // Consider a mixed target with the following structure:
        //
        //      MixedTarget
        //      ├── NewCar.swift
        //      ├── OldCar.m
        //      └── include
        //          └── OldCar.h
        // 
        // Within the `OldCar.m` implementation, the `OldCar.h` header should
        // be able to be imported via the following import statements:
        // - #import "OldCar.h"
        // - #import "include/OldCar.h"
        //
        // This aligns with the behavior of a Clang-only target.
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: [
                    "--target", 
                    "MixedTargetsPublicHeadersAreIncludedInHeaderSearchPathsForObjcSource"
                ]
            )
        }
    }

    func testMixedTargetWithNestedPublicHeaders() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetWithNestedPublicHeaders"]
            )
        }
    }

    func testMixedTargetWithNestedPublicHeadersAndCustomModuleMap() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: [
                    "--target",
                    "MixedTargetWithNestedPublicHeadersAndCustomModuleMap"
                ]
            )
        }
    }

    // MARK: - Testing Mixed *Test* Targets

    func testMixedTestTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "BasicMixedTargetTests"]
            )
        }
    }

    func testTestUtilitiesCanBeSharedAcrossSwiftAndObjcTestFiles() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "MixedTestTargetWithSharedUtilitiesTests"]
            )
        }
    }

    func testPrivateHeadersCanBeTestedViaHeaderSearchPaths() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertSwiftTest(
                fixturePath,
                extraArgs: ["--filter", "PrivateHeadersCanBeTestedViaHeaderSearchPathsTests"]
            )
        }
    }

    // MARK: - Integrating Mixed Target with other Targets

    func testClangTargetDependsOnMixedTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "ClangTargetDependsOnMixedTarget"]
            )
        }
    }

     func testSwiftTargetDependsOnMixedTarget() throws {
         try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
             XCTAssertBuilds(
                 fixturePath,
                 extraArgs: ["--target", "SwiftTargetDependsOnMixedTarget"]
             )
         }
     }

     func testMixedTargetDependsOnOtherMixedTarget() throws {
         try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
             XCTAssertBuilds(
                 fixturePath,
                 extraArgs: ["--target", "MixedTargetDependsOnMixedTarget"]
             )
         }
     }

     func testMixedTargetDependsOnClangTarget() throws {
         try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
             XCTAssertBuilds(
                 fixturePath,
                 extraArgs: ["--target", "MixedTargetDependsOnClangTarget"]
             )
         }
     }

    func testMixedTargetDependsOnSwiftTarget() throws {
        try fixture(name: "MixedTargets/BasicMixedTargets") { fixturePath in
            XCTAssertBuilds(
                fixturePath,
                extraArgs: ["--target", "MixedTargetDependsOnSwiftTarget"]
            )
        }
    }

}
