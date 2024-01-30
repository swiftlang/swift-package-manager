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

import class Basics.ObservabilitySystem
import struct Basics.Triple
import class Build.BuildPlan
import class Build.SwiftTargetBuildDescription
import func SPMTestSupport.macrosPackageGraph
import func SPMTestSupport.mockBuildParameters
import struct SPMTestSupport.BuildPlanResult
import func SPMTestSupport.XCTAssertMatch
import class TSCBasic.InMemoryFileSystem

import XCTest

extension BuildPlanResult {
    func allTargets(named targetName: String) throws -> [SwiftTargetBuildDescription] {
        try self.targetMap
            .filter { $0.0.targetName == targetName }
            .map { try $1.swiftTarget() }
    }

    func check(triple: Triple, for target: String, file: StaticString = #file, line: UInt = #line) throws {
        let target = try self.target(for: target).swiftTarget()
        XCTAssertMatch(try target.emitCommandLine(), [.contains(triple.tripleString)], file: file, line: line)
    }
}

final class CrossCompilationBuildPlanTests: XCTestCase {
    func testMacros() throws {
        let (graph, fs, scope) = try macrosPackageGraph()

        let productsTriple = Triple.x86_64MacOS
        let toolsTriple = Triple.arm64Linux
        let result = try BuildPlanResult(plan: BuildPlan(
            productsBuildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true, triple: productsTriple),
            toolsBuildParameters: mockBuildParameters(triple: toolsTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        ))
        result.checkProductsCount(3)
        result.checkTargetsCount(8)

        XCTAssertTrue(try result.allTargets(named: "SwiftSyntax").contains { $0.target.buildTriple == .tools })
        try result.check(triple: toolsTriple, for: "MMIOMacros")
        try result.check(triple: productsTriple, for: "MMIO")
        try result.check(triple: productsTriple, for: "Core")
        try result.check(triple: productsTriple, for: "HAL")
    }
}
