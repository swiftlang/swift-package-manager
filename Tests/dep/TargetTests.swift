/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import dep
import class PackageDescription.Package

extension Target {
    private convenience init(name: String, files: [String], type: TargetType) throws {
        try self.init(productName: name, sources: files, type: type)
    }

    private func dependsOn(target: Target) {
        dependencies.append(target)
    }

    var recursiveDeps: [Target] {
        sortDependencies(self)
        return dependencies
    }
}


class TargetTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("test1", test1),
            ("test2", test2),
            ("test3", test3),
            ("test4", test4),
            ("test5", test5),
            ("test6", test6),
        ]
    }

    func test1() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)

        t3.dependsOn(t2)
        t2.dependsOn(t1)

        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test2() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)
        let t4 = try! Target(name: "t3", files: [], type: .Library)

        t4.dependsOn(t2)
        t4.dependsOn(t3)
        t4.dependsOn(t1)
        t3.dependsOn(t2)
        t3.dependsOn(t1)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test3() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)
        let t4 = try! Target(name: "t4", files: [], type: .Library)

        t4.dependsOn(t1)
        t4.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t3.dependsOn(t1)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test4() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)
        let t4 = try! Target(name: "t4", files: [], type: .Library)

        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test5() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)
        let t4 = try! Target(name: "t4", files: [], type: .Library)
        let t5 = try! Target(name: "t5", files: [], type: .Library)
        let t6 = try! Target(name: "t6", files: [], type: .Library)

        t6.dependsOn(t5)
        t6.dependsOn(t4)
        t5.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        // precise order is not important, but it is important that the following are true
        let t6rd = t6.recursiveDeps
        XCTAssertEqual(t6rd.indexOf(t3)!, t6rd.indexOf(t4)!.advancedBy(1))
        XCTAssert(t6rd.indexOf(t5)! < t6rd.indexOf(t2)!)
        XCTAssert(t6rd.indexOf(t5)! < t6rd.indexOf(t1)!)
        XCTAssert(t6rd.indexOf(t2)! < t6rd.indexOf(t1)!)
        XCTAssert(t6rd.indexOf(t3)! < t6rd.indexOf(t2)!)

        XCTAssertEqual(t5.recursiveDeps, [t2, t1])
        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func test6() {
        let t1 = try! Target(name: "t1", files: [], type: .Library)
        let t2 = try! Target(name: "t2", files: [], type: .Library)
        let t3 = try! Target(name: "t3", files: [], type: .Library)
        let t4 = try! Target(name: "t4", files: [], type: .Library)
        let t5 = try! Target(name: "t5", files: [], type: .Library)
        let t6 = try! Target(name: "t6", files: [], type: .Library)

        t6.dependsOn(t4)  // same as above, but
        t6.dependsOn(t5)  // these two swapped
        t5.dependsOn(t2)
        t4.dependsOn(t3)
        t3.dependsOn(t2)
        t2.dependsOn(t1)

        // precise order is not important, but it is important that the following are true
        let t6rd = t6.recursiveDeps
        XCTAssertEqual(t6rd.indexOf(t3)!, t6rd.indexOf(t4)!.advancedBy(1))
        XCTAssert(t6rd.indexOf(t5)! < t6rd.indexOf(t2)!)
        XCTAssert(t6rd.indexOf(t5)! < t6rd.indexOf(t1)!)
        XCTAssert(t6rd.indexOf(t2)! < t6rd.indexOf(t1)!)
        XCTAssert(t6rd.indexOf(t3)! < t6rd.indexOf(t2)!)

        XCTAssertEqual(t5.recursiveDeps, [t2, t1])
        XCTAssertEqual(t4.recursiveDeps, [t3, t2, t1])
        XCTAssertEqual(t3.recursiveDeps, [t2, t1])
        XCTAssertEqual(t2.recursiveDeps, [t1])
    }

    func testEmptyDirectoriesHaveNoTargets() {
        mktmpdir {
            let computedTargets = try determineTargets(packageName: "foo", prefix: ".")
            XCTAssertTrue(computedTargets.isEmpty)
        }
    }
}


extension Target: CustomStringConvertible {
    public var description: String { return productName }
}
