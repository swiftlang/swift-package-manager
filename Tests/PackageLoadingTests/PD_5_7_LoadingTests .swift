/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class PackageDescription5_7LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_7
    }

    func testConditionalTargetDependencies() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Bar", condition: .when(platforms: [])),
                        .target(name: "Baz", condition: .when(platforms: [.linux])),
                    ]),
                    .target(name: "Bar"),
                    .target(name: "Baz"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try loadManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)

        let dependencies = manifest.targets[0].dependencies
        XCTAssertEqual(dependencies[0], .target(name: "Bar", condition: .none))
        XCTAssertEqual(dependencies[1], .target(name: "Baz", condition: .init(platformNames: ["linux"], config: .none)))
    }

    func testConditionalTargetDependenciesDeprecation() throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                dependencies: [],
                targets: [
                    .target(name: "Foo", dependencies: [
                        .target(name: "Bar", condition: .when(platforms: nil))
                    ]),
                    .target(name: "Bar")
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            if case ManifestParseError.invalidManifestFormat(let error, _) = error {
                XCTAssertMatch(error, .contains("when(platforms:)' was obsoleted"))
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}
