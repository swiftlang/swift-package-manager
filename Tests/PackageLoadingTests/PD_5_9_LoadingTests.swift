//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import XCTest

class PackageDescription5_9LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_9
    }

    func testMacroTargets() throws {
        let content = """
            import CompilerPluginSupport
            import PackageDescription

            let package = Package(name: "MyPackage",
                targets: [
                    .macro(name: "MyMacro", swiftSettings: [.define("BEST")], linkerSettings: [.linkedLibrary("best")]),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, diagnostics) = try loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertEqual(diagnostics.count, 0, "unexpected diagnostics: \(diagnostics)")
    }
}
