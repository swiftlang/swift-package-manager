// Copyright (C) 2024 Apple Inc. All rights reserved.
//
// This document is the property of Apple Inc.
// It is considered confidential and proprietary.
//
// This document may not be reproduced or transmitted in any form,
// in whole or in part, without the express written permission of
// Apple Inc.

import Build
import Foundation
import LLBuildManifest
@_spi(SwiftPMInternal)
import SPMTestSupport
import XCTest

class PrepareForIndexTests: XCTestCase {
    func testPrepare() throws {
        let (graph, fs, scope) = try macrosPackageGraph()

        let plan = try BuildPlan(
            destinationBuildParameters: mockBuildParameters(prepareForIndexing: true),
            toolsBuildParameters: mockBuildParameters(prepareForIndexing: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        let builder = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: scope)
        let manifest = try builder.generatePrepareManifest(at: "/manifest")

        // Make sure we're still building swift modules
        XCTAssertNotNil(manifest.commands["<SwiftSyntax-debug.module>"])
        // Make sure we're not building things that link
        XCTAssertNil(manifest.commands["C.Core-debug.exe"])

        let outputs = manifest.commands.flatMap(\.value.tool.outputs).map(\.name)

        // Make sure we're building the swift modules
        let swiftModules = Set(outputs.filter({ $0.hasSuffix(".swiftmodule")}))
        XCTAssertEqual(swiftModules, Set([
            "/path/to/build/arm64-apple-macosx15.0/debug/Core.build/Core.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules/CoreTests.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules/HAL.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules/HALTests.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules/MMIO.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules/SwiftSyntax.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules-tool/MMIOMacros.swiftmodule",
            "/path/to/build/arm64-apple-macosx15.0/debug/Modules-tool/SwiftSyntax.swiftmodule",
        ]))

        // Ensure swiftmodules built with correct arguments
        let coreCommands = manifest.commands.values.filter({
            $0.tool.outputs.contains(where: {
                $0.name == "/path/to/build/arm64-apple-macosx15.0/debug/Core.build/Core.swiftmodule"
            })
        })
        XCTAssertEqual(coreCommands.count, 1)
        let coreSwiftc = try XCTUnwrap(coreCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertTrue(coreSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Ensure tools are built normally
        let toolCommands = manifest.commands.values.filter({
            $0.tool.outputs.contains(where: {
                $0.name == "/path/to/build/arm64-apple-macosx15.0/debug/Modules-tool/SwiftSyntax.swiftmodule"
            })
        })
        XCTAssertEqual(toolCommands.count, 1)
        let toolSwiftc = try XCTUnwrap(toolCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertFalse(toolSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Make sure only object files for tools are built
        let objectFiles = Set(outputs.filter({ $0.hasSuffix(".o") }))
        XCTAssertEqual(objectFiles, Set([
            "/path/to/build/arm64-apple-macosx15.0/debug/MMIOMacros-tool.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/SwiftSyntax-tool.build/source.swift.o"
        ]))

        // Check diff with regular build plan
        let plan0 = try BuildPlan(
            destinationBuildParameters: mockBuildParameters(prepareForIndexing: false),
            toolsBuildParameters: mockBuildParameters(prepareForIndexing: false),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        let builder0 = LLBuildManifestBuilder(plan0, fileSystem: fs, observabilityScope: scope)
        let manifest0 = try builder0.generateManifest(at: "/manifest")
        let outputs0 = manifest0.commands.flatMap(\.value.tool.outputs).map(\.name)

        // The prepare shouldn't create any other object files.
        let objectFiles0 = Set(outputs0.filter({ $0.hasSuffix(".o") })).subtracting(objectFiles)
        XCTAssertEqual(objectFiles0, Set([
            "/path/to/build/arm64-apple-macosx15.0/debug/Core.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/CoreTests.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/HAL.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/HALTests.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/MMIO.build/source.swift.o",
            "/path/to/build/arm64-apple-macosx15.0/debug/SwiftSyntax.build/source.swift.o",
        ]))
    }
}
