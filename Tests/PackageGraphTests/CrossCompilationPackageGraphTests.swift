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
@_spi(SwiftPMInternal)
import _InternalTestSupport

@testable
import PackageGraph

import PackageModel
import XCTest

final class CrossCompilationPackageGraphTests: XCTestCase {
    func testTrivialPackage() throws {
        let graph = try trivialPackageGraph().graph
        PackageGraphTester(graph) { result in
            result.check(packages: "Pkg")
            // "SwiftSyntax" is included for both host and target triples and is not pruned on this level
            result.check(modules: "app", "lib")
            result.check(testModules: "test")
            result.checkTarget("app") { result in
                result.check(dependencies: "lib")
            }
            result.checkTarget("lib") { result in
                result.check(dependencies: [])
            }
            result.checkTarget("test") { result in
                result.check(dependencies: "lib")
            }
        }
    }

    func testMacros() throws {
        let graph = try macrosPackageGraph().graph
        PackageGraphTester(graph) { result in
            result.check(packages: "swift-firmware", "swift-mmio", "swift-syntax")
            result.check(
                modules: "Core",
                "HAL",
                "MMIO",
                "MMIOMacros",
                "SwiftSyntax"
            )
            result.check(testModules: "CoreTests", "HALTests")
            result.checkTarget("Core") { result in
                result.check(dependencies: "HAL")
            }
            result.checkTarget("HAL") { result in
                result.check(dependencies: "MMIO")
            }
            result.checkTarget("MMIO") { result in
                result.check(dependencies: "MMIOMacros")
            }
            result.checkTarget("MMIOMacros") { result in
                result.checkDependency("SwiftSyntax") { result in
                    result.checkProduct { result in
                        result.checkTarget("SwiftSyntax") { _ in
                        }
                    }
                }
            }

            result.checkTargets("SwiftSyntax") { results in
                XCTAssertEqual(results.count, 1)
            }
        }
    }

    func testMacrosTests() throws {
        let graph = try macrosTestsPackageGraph().graph
        PackageGraphTester(graph) { result in
            result.check(packages: "swift-mmio", "swift-syntax")
            // "SwiftSyntax" is included for both host and target triples and is not pruned on this level
            result.check(
                modules: "MMIO",
                "MMIOMacros",
                "MMIOPlugin",
                "SwiftCompilerPlugin",
                "SwiftCompilerPluginMessageHandling",
                "SwiftSyntax",
                "SwiftSyntaxMacros",
                "SwiftSyntaxMacrosTestSupport"
            )

            result.check(testModules: "MMIOMacrosTests", "MMIOMacro+PluginTests", "NOOPTests", "SwiftSyntaxTests")
            result.checkTarget("MMIO") { result in
                result.check(dependencies: "MMIOMacros")
            }
            result.checkTargets("MMIOMacros") { results in
                XCTAssertEqual(results.count, 1)
            }

            result.checkTarget("MMIOMacrosTests") { result in
                result.checkDependency("MMIOMacros") { result in
                    result.checkTarget { result in
                        result.checkDependency("SwiftSyntaxMacros") { result in
                            result.checkProduct { _ in
                            }
                        }
                        result.checkDependency("SwiftCompilerPlugin") { result in
                            result.checkProduct { result in
                                result.checkTarget("SwiftCompilerPlugin") { result in
                                    result.checkDependency("SwiftCompilerPluginMessageHandling") { result in
                                        result.checkTarget { _ in
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            result.checkTarget("MMIOMacros") { _ in
            }

            result.checkTarget("MMIOMacrosTests") { _ in
            }

            result.checkTargets("SwiftSyntax") { results in
                XCTAssertEqual(results.count, 1)

                for result in results {
                    XCTAssertEqual(result.target.packageIdentity, .plain("swift-syntax"))
                    XCTAssertEqual(graph.package(for: result.target)?.identity, .plain("swift-syntax"))
                }
            }

            result.checkTargets("SwiftCompilerPlugin") { results in
                XCTAssertEqual(results.count, 1)

                for result in results {
                    XCTAssertEqual(result.target.packageIdentity, .plain("swift-syntax"))
                    XCTAssertEqual(graph.package(for: result.target)?.identity, .plain("swift-syntax"))
                }
            }

            result.checkTargets("NOOPTests") { results in
                XCTAssertEqual(results.count, 1)
            }
        }
    }
}
