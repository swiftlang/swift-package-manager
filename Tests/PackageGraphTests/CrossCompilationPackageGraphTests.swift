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

@testable
import SPMTestSupport

@testable
import PackageGraph

import XCTest

final class CrossCompilationPackageGraphTests: XCTestCase {
    func testMacros() throws {
        let graph = try macrosPackageGraph().graph
        PackageGraphTester(graph) { result in
            result.check(packages: "swift-firmware", "swift-mmio", "swift-syntax")
            // "SwiftSyntax" is included for both host and target triples and is not pruned on this level
            result.check(targets: "Core", "HAL", "MMIO", "MMIOMacros", "SwiftSyntax", "SwiftSyntax")
            result.check(testModules: "CoreTests", "HALTests")
            result.checkTarget("Core") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "HAL")
            }
            result.checkTarget("HAL") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "MMIO")
            }
            result.checkTarget("MMIO") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "MMIOMacros")
            }
            result.checkTarget("MMIOMacros") { result in
                result.check(buildTriple: .tools)
                result.checkDependency("SwiftSyntax") { result in
                    result.checkProduct { result in
                        result.check(buildTriple: .tools)
                        result.checkTarget("SwiftSyntax") { result in
                            result.check(buildTriple: .tools)
                        }
                    }
                }
            }

            result.checkTargets("SwiftSyntax") { results in
                XCTAssertEqual(results.count, 2)

                XCTAssertEqual(results.filter({ $0.target.buildTriple == .tools }).count, 1)
                XCTAssertEqual(results.filter({ $0.target.buildTriple == .destination }).count, 1)
            }
        }
    }
}
