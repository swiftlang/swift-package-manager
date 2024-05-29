//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Build
import Foundation
import LLBuildManifest
@_spi(SwiftPMInternal)
import SPMTestSupport
import TSCBasic
import XCTest

class PrepareForIndexTests: XCTestCase {
    func testPrepare() throws {
        let (graph, fs, scope) = try macrosPackageGraph()

        let plan = try BuildPlan(
            destinationBuildParameters: mockBuildParameters(prepareForIndexing: true),
            toolsBuildParameters: mockBuildParameters(prepareForIndexing: false),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        let builder = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: scope)
        let manifest = try builder.generatePrepareManifest(at: "/manifest")

        // Make sure we're building the swift modules
        let outputs = manifest.commands.flatMap(\.value.tool.outputs).map(\.name)
        XCTAssertTrue(outputs.contains(where: { $0.hasSuffix(".swiftmodule") }))

        // Ensure swiftmodules built with correct arguments
        let coreCommands = manifest.commands.values.filter {
            $0.tool.outputs.contains(where: {
                $0.name.hasSuffix("debug/Core.build/Core.swiftmodule")
            })
        }
        XCTAssertEqual(coreCommands.count, 1)
        let coreSwiftc = try XCTUnwrap(coreCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertTrue(coreSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Ensure tools are built normally
        let toolCommands = manifest.commands.values.filter {
            $0.tool.outputs.contains(where: {
                $0.name.hasSuffix("debug/Modules-tool/SwiftSyntax.swiftmodule")
            })
        }
        XCTAssertEqual(toolCommands.count, 1)
        let toolSwiftc = try XCTUnwrap(toolCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertFalse(toolSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Make sure only object files for tools are built
        XCTAssertTrue(
            outputs.filter { $0.hasSuffix(".o") }.allSatisfy { $0.contains("-tool.build/") },
            "outputs:\n\t\(outputs.filter { $0.hasSuffix(".o") }.joined(separator: "\n\t"))"
        )
    }
}
