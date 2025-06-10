import _InternalTestSupport

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import DriverSupport
import PackageModel
import TSCBasic
import XCTest

final class TraitTests: XCTestCase {
    func testTraits_whenNoFlagPassed() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }

    func testTraits_whenTraitUnification() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "default,Package9,Package10", "--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }

    func testTraits_whenTraitUnification_whenSecondTraitNotEnabled() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "default,Package9", "--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }

    func testTraits_whenIndividualTraitsEnabled_andDefaultTraits() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: [
                    "--traits",
                    "default,Package5,Package7,BuildCondition3",
                    "--experimental-prune-unused-dependencies",
                ]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 enabled

            """)
        }
    }

    func testTraits_whenDefaultTraitsDisabled() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )

        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--disable-default-traits", "--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }

    func testTraits_whenIndividualTraitsEnabled_andDefaultTraitsDisabled() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "Package5,Package7", "--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }

    func testTraits_whenAllTraitsEnabled() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )

        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--enable-all-traits", "--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
    }

    func testTraits_whenAllTraitsEnabled_andDefaultTraitsDisabled() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )

        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: [
                    "--enable-all-traits",
                    "--disable-default-traits",
                    "--experimental-prune-unused-dependencies",
                ]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            XCTAssertNoMatch(stderr, .contains("warning:"))
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
    }

    func testTraits_dumpPackage() async throws {
        try await fixture(name: "Traits") { fixturePath in
            let packageRoot = fixturePath.appending("Example")
            let (dumpOutput, _) = try await SwiftPM.Package.execute(["dump-package"], packagePath: packageRoot)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case .dictionary(let contents) = json else { XCTFail("unexpected result"); return }
            guard case .array(let traits)? = contents["traits"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(traits.count, 12)
        }
    }

    func testTests_whenNoFlagPassed() async throws {
        try XCTSkipOnWindows(
            because: """
            Error during swift Run Invalid path. Possibly related to https://github.com/swiftlang/swift-package-manager/issues/8511 or https://github.com/swiftlang/swift-package-manager/issues/8602
            """,
            skipPlatformCi: true,
        )
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftTest(
                fixturePath.appending("Example"),
                extraArgs: ["--experimental-prune-unused-dependencies"]
            )
            let expectedOut = """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """
            XCTAssertMatch(stdout, .contains(expectedOut))
        }
    }

    func testTests_whenAllTraitsEnabled_andDefaultTraitsDisabled() async throws {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftTest(
                fixturePath.appending("Example"),
                extraArgs: [
                    "--enable-all-traits",
                    "--disable-default-traits",
                    "--experimental-prune-unused-dependencies",
                ]
            )
            let expectedOut = """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """
            XCTAssertMatch(stdout, .contains(expectedOut))
        }
    }

    func testPackageDumpSymbolGraph_enablesAllTraits() async throws {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath.appending("Package10"),
                extraArgs: ["dump-symbol-graph", "--experimental-prune-unused-dependencies"]
            )
            let optionalPath = stdout
                .lazy
                .split(whereSeparator: \.isNewline)
                .first { String($0).hasPrefix("Files written to ") }?
                .dropFirst(17)

            let path = try String(XCTUnwrap(optionalPath))
            let symbolGraph = try String(contentsOfFile: "\(path)/Package10Library1.symbols.json", encoding: .utf8)
            XCTAssertMatch(symbolGraph, .contains("TypeGatedByPackage10Trait1"))
            XCTAssertMatch(symbolGraph, .contains("TypeGatedByPackage10Trait2"))
        }
    }

    func testPackagePluginGetSymbolGraph_enablesAllTraits() async throws {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath.appending("Package10"),
                extraArgs: ["plugin", "extract", "--experimental-prune-unused-dependencies"]
            )
            let path = String(stdout.split(whereSeparator: \.isNewline).first!)
            let symbolGraph = try String(contentsOfFile: "\(path)/Package10Library1.symbols.json", encoding: .utf8)
            XCTAssertMatch(symbolGraph, .contains("TypeGatedByPackage10Trait1"))
            XCTAssertMatch(symbolGraph, .contains("TypeGatedByPackage10Trait2"))
        }
    }

    func testPackageDisablingDefaultsTrait_whenNoTraits() async throws {
        try await fixture(name: "Traits") { fixturePath in
            await XCTAssertAsyncThrowsError(try await executeSwiftRun(
                fixturePath.appending("DisablingEmptyDefaultsExample"),
                "DisablingEmptyDefaultsExample"
            )) { error in
                guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                    XCTFail()
                    return
                }

                let expectedErr = """
                        error: Disabled default traits by package 'disablingemptydefaultsexample' on package 'Package11' that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.
                        
                        """
                XCTAssertMatch(stderr, .contains(expectedErr))
            }
        }
    }
}
