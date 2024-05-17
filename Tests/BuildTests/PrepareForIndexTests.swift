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
import TSCBasic
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

        let outputs = try manifest.commands.flatMap(\.value.tool.outputs).map(\.name)
            .filter({ $0.hasPrefix("/path/to/") })
            .map({ try AbsolutePath(validating: $0).components.suffix(3).joined(separator: "/") })

        // Make sure we're building the swift modules
        let swiftModules = Set(outputs.filter({ $0.hasSuffix(".swiftmodule")}))
        XCTAssertEqual(swiftModules, Set([
            "debug/Core.build/Core.swiftmodule",
            "debug/Modules/CoreTests.swiftmodule",
            "debug/Modules/HAL.swiftmodule",
            "debug/Modules/HALTests.swiftmodule",
            "debug/Modules/MMIO.swiftmodule",
            "debug/Modules/SwiftSyntax.swiftmodule",
            "debug/Modules-tool/MMIOMacros.swiftmodule",
            "debug/Modules-tool/SwiftSyntax.swiftmodule",
        ]))

        // Ensure swiftmodules built with correct arguments
        let coreCommands = manifest.commands.values.filter({
            $0.tool.outputs.contains(where: {
                $0.name.hasSuffix("debug/Core.build/Core.swiftmodule")
            })
        })

        XCTAssertEqual(coreCommands.count, 1)
        let coreSwiftc = try XCTUnwrap(coreCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertTrue(coreSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Ensure tools are built normally
        let toolCommands = manifest.commands.values.filter({
            $0.tool.outputs.contains(where: {
                $0.name.hasSuffix("debug/Modules-tool/SwiftSyntax.swiftmodule")
            })
        })
        XCTAssertEqual(toolCommands.count, 1)
        let toolSwiftc = try XCTUnwrap(toolCommands.first?.tool as? SwiftCompilerTool)
        XCTAssertFalse(toolSwiftc.otherArguments.contains("-experimental-skip-all-function-bodies"))

        // Make sure only object files for tools are built
        let objectFiles = Set(outputs.filter({ $0.hasSuffix(".o") }))
        XCTAssertEqual(objectFiles, Set([
            "debug/MMIOMacros-tool.build/source.swift.o",
            "debug/SwiftSyntax-tool.build/source.swift.o"
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
        let objectFiles0 = try Set(outputs0.filter({ $0.hasSuffix(".o") })
            .map({ try AbsolutePath(validating: $0).components.suffix(3).joined(separator: "/") })
        ).subtracting(objectFiles)
        XCTAssertEqual(objectFiles0, Set([
            "debug/Core.build/source.swift.o",
            "debug/CoreTests.build/source.swift.o",
            "debug/HAL.build/source.swift.o",
            "debug/HALTests.build/source.swift.o",
            "debug/MMIO.build/source.swift.o",
            "debug/SwiftSyntax.build/source.swift.o",
        ]))
    }
}
