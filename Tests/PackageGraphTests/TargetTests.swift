//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

import class Basics.ObservabilitySystem
import class Basics.ObservabilityScope
import PackageGraph
import PackageModel

private extension ResolvedTarget {
    convenience init(name: String, deps: ResolvedTarget..., observabilityScope: ObservabilityScope) throws {
        try self.init(
            target: SwiftTarget(
                name: name,
                type: .library,
                path: .root,
                sources: Sources(paths: [], root: "/"),
                dependencies: [],
                packageAccess: false,
                swiftVersion: .v4,
                usesUnsafeFlags: false
            ),
            dependencies: deps.map { .target($0, conditions: []) },
            defaultLocalization: nil,
            platforms: .init(declared: [], derivedXCTestPlatformProvider: .none),
            observabilityScope: observabilityScope
        )
    }
}

func testTargets(file: StaticString = #file, line: UInt = #line, body: () throws -> Void) {
    do {
        try body()
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

class TargetDependencyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
    }

    func test1() throws {
        let system = ObservabilitySystem.makeForTesting()
        let observabilityScope = system.topScope

        testTargets {
            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, observabilityScope: observabilityScope)

            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }

    func test2() throws {
        let system = ObservabilitySystem.makeForTesting()
        let observabilityScope = system.topScope

        testTargets {
            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, t1, observabilityScope: observabilityScope)
            let t4 = try ResolvedTarget(name: "t4", deps: t2, t3, t1, observabilityScope: observabilityScope)

            XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }

    func test3() throws {
        let system = ObservabilitySystem.makeForTesting()
        let observabilityScope = system.topScope

        testTargets {
            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, t1, observabilityScope: observabilityScope)
            let t4 = try ResolvedTarget(name: "t4", deps: t1, t2, t3, observabilityScope: observabilityScope)

            XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }

    func test4() throws {
        testTargets {
            let system = ObservabilitySystem.makeForTesting()
            let observabilityScope = system.topScope

            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, observabilityScope: observabilityScope)
            let t4 = try ResolvedTarget(name: "t4", deps: t3, observabilityScope: observabilityScope)

            XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }

    func test5() throws {
        let system = ObservabilitySystem.makeForTesting()
        let observabilityScope = system.topScope

        testTargets {
            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, observabilityScope: observabilityScope)
            let t4 = try ResolvedTarget(name: "t4", deps: t3, observabilityScope: observabilityScope)
            let t5 = try ResolvedTarget(name: "t5", deps: t2, observabilityScope: observabilityScope)
            let t6 = try ResolvedTarget(name: "t6", deps: t5, t4, observabilityScope: observabilityScope)

            // precise order is not important, but it is important that the following are true
            let t6rd = try t6.recursiveTargetDependencies()
            XCTAssertEqual(t6rd.firstIndex(of: t3)!, t6rd.index(after: t6rd.firstIndex(of: t4)!))
            XCTAssert(t6rd.firstIndex(of: t5)! < t6rd.firstIndex(of: t2)!)
            XCTAssert(t6rd.firstIndex(of: t5)! < t6rd.firstIndex(of: t1)!)
            XCTAssert(t6rd.firstIndex(of: t2)! < t6rd.firstIndex(of: t1)!)
            XCTAssert(t6rd.firstIndex(of: t3)! < t6rd.firstIndex(of: t2)!)

            XCTAssertEqual(try t5.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }

    func test6() throws {
        let system = ObservabilitySystem.makeForTesting()
        let observabilityScope = system.topScope

        testTargets {
            let t1 = try ResolvedTarget(name: "t1", observabilityScope: observabilityScope)
            let t2 = try ResolvedTarget(name: "t2", deps: t1, observabilityScope: observabilityScope)
            let t3 = try ResolvedTarget(name: "t3", deps: t2, observabilityScope: observabilityScope)
            let t4 = try ResolvedTarget(name: "t4", deps: t3, observabilityScope: observabilityScope)
            let t5 = try ResolvedTarget(name: "t5", deps: t2, observabilityScope: observabilityScope)
            // same as above, but these two swapped
            let t6 = try ResolvedTarget(name: "t6", deps: t4, t5, observabilityScope: observabilityScope)

            // precise order is not important, but it is important that the following are true
            let t6rd = try t6.recursiveTargetDependencies()
            XCTAssertEqual(t6rd.firstIndex(of: t3)!, t6rd.index(after: t6rd.firstIndex(of: t4)!))
            XCTAssert(t6rd.firstIndex(of: t5)! < t6rd.firstIndex(of: t2)!)
            XCTAssert(t6rd.firstIndex(of: t5)! < t6rd.firstIndex(of: t1)!)
            XCTAssert(t6rd.firstIndex(of: t2)! < t6rd.firstIndex(of: t1)!)
            XCTAssert(t6rd.firstIndex(of: t3)! < t6rd.firstIndex(of: t2)!)

            XCTAssertEqual(try t5.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
            XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
            XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
        }
    }
}
