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
import class Build.ProductBuildDescription
import class Build.SwiftTargetBuildDescription
import func SPMTestSupport.macrosPackageGraph
import func SPMTestSupport.mockBuildParameters
import struct SPMTestSupport.BuildPlanResult
import func SPMTestSupport.XCTAssertMatch
import class TSCBasic.InMemoryFileSystem

import XCTest

extension BuildPlanResult {
    func allTargets(named name: String) throws -> [SwiftTargetBuildDescription] {
        try self.targetMap
            .filter { $0.0.targetName == name }
            .map { try $1.swiftTarget() }
    }
    
    func allProducts(named name: String) -> [ProductBuildDescription] {
        self.productMap
            .filter { $0.0.productName == name }
            .map { $1 }
    }

    func check(triple: Triple, for target: String, file: StaticString = #file, line: UInt = #line) throws {
        let target = try self.target(for: target).swiftTarget()
        XCTAssertMatch(try target.emitCommandLine(), [.contains(triple.tripleString)], file: file, line: line)
    }
}

final class CrossCompilationBuildPlanTests: XCTestCase {
    func testMacros() throws {
        let (graph, fs, scope) = try macrosPackageGraph()

        let productsTriple = Triple.arm64Linux
        let toolsTriple = Triple.x86_64MacOS
        let plan = try BuildPlan(
            destinationBuildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true, triple: productsTriple),
            toolsBuildParameters: mockBuildParameters(triple: toolsTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )
        let result = try BuildPlanResult(plan: plan)
        result.checkProductsCount(3)
        result.checkTargetsCount(10)

        XCTAssertTrue(try result.allTargets(named: "SwiftSyntax").contains { $0.target.buildTriple == .tools })
        try result.check(triple: toolsTriple, for: "MMIOMacros")
        try result.check(triple: productsTriple, for: "MMIO")
        try result.check(triple: productsTriple, for: "Core")
        try result.check(triple: productsTriple, for: "HAL")

        let macroProducts = result.allProducts(named: "MMIOMacros")
        XCTAssertEqual(macroProducts.count, 1)
        let macroProduct = try XCTUnwrap(macroProducts.first)
        XCTAssertEqual(macroProduct.buildParameters.triple, toolsTriple)

        // FIXME: check for *toolsTriple*
        let mmioTarget = try XCTUnwrap(plan.targets.first { try $0.swiftTarget().target.name == "MMIO" }?.swiftTarget())
        let compileArguments = try mmioTarget.emitCommandLine()
        XCTAssertMatch(
            compileArguments,
            [
                "-I", .equal(mmioTarget.moduleOutputPath.parentDirectory.pathString),
                .anySequence,
                "-Xfrontend", "-load-plugin-executable",
                "-Xfrontend", .contains(toolsTriple.tripleString)
            ]
        )
    }
}
