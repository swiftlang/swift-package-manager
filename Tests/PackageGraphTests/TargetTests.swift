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

import PackageGraph
@testable import PackageModel

extension ResolvedTarget {
    fileprivate init(
        packageIdentity: String,
        name: String,
        deps: ResolvedTarget...,
        conditions: [PackageCondition] = []
    ) {
        self.init(
            packageIdentity: .init(packageIdentity),
            underlying: SwiftTarget(
                name: name,
                type: .library,
                path: .root,
                sources: Sources(paths: [], root: "/"),
                dependencies: [],
                packageAccess: false,
                swiftVersion: .v4,
                usesUnsafeFlags: false
            ),
            dependencies: deps.map { .target($0, conditions: conditions) },
            defaultLocalization: nil,
            supportedPlatforms: [],
            platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)
        )
    }
}

class TargetDependencyTests: XCTestCase {
    func test1() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2)

        XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
        XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
    }

    func test2() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2, t1)
        let t4 = ResolvedTarget(packageIdentity: "pkg", name: "t4", deps: t2, t3, t1)

        XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
        XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
        XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
    }

    func test3() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2, t1)
        let t4 = ResolvedTarget(packageIdentity: "pkg", name: "t4", deps: t1, t2, t3)

        XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
        XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
        XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
    }

    func test4() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2)
        let t4 = ResolvedTarget(packageIdentity: "pkg", name: "t4", deps: t3)

        XCTAssertEqual(try t4.recursiveTargetDependencies(), [t3, t2, t1])
        XCTAssertEqual(try t3.recursiveTargetDependencies(), [t2, t1])
        XCTAssertEqual(try t2.recursiveTargetDependencies(), [t1])
    }

    func test5() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2)
        let t4 = ResolvedTarget(packageIdentity: "pkg", name: "t4", deps: t3)
        let t5 = ResolvedTarget(packageIdentity: "pkg", name: "t5", deps: t2)
        let t6 = ResolvedTarget(packageIdentity: "pkg", name: "t6", deps: t5, t4)

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

    func test6() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t3 = ResolvedTarget(packageIdentity: "pkg", name: "t3", deps: t2)
        let t4 = ResolvedTarget(packageIdentity: "pkg", name: "t4", deps: t3)
        let t5 = ResolvedTarget(packageIdentity: "pkg", name: "t5", deps: t2)
        let t6 = ResolvedTarget(
            packageIdentity: "pkg",
            name: "t6",
            deps: t4,
            t5
        ) // same as above, but these two swapped

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

    func testConditions() throws {
        let t1 = ResolvedTarget(packageIdentity: "pkg", name: "t1")
        let t2 = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t2NoConditions = ResolvedTarget(packageIdentity: "pkg", name: "t2", deps: t1)
        let t2WithConditions = ResolvedTarget(
            packageIdentity: "pkg",
            name: "t2",
            deps: t1,
            conditions: [.init(platforms: [.linux])]
        )

        // FIXME: we should test for actual `t2` and `t2NoConditions` equality, but `SwiftTarget` is a reference type,
        // which currently breaks this test, and it shouldn't
        XCTAssertEqual(t2.dependencies, t2NoConditions.dependencies)
        XCTAssertEqual(t2.dependencies, t2WithConditions.dependencies)
    }
}
