/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Update
import struct PackageDescription.Version
import XCTest

class UpdateTestCase: XCTestCase {

//    func testEmptyGraph() throws {
//
//        class Package: Update.Package {
//            let url = ""
//            let version = Version(0,0,0)
//
//            func upgrade(to: Version) throws {}
//            func fetch() throws -> [Version] { return [] }
//            func deps() -> [(URL, Range<Version>)] { return [] }
//        }
//
//        class RootPackage: Update.Parent {
//            func deps() -> [(URL, Range<Version>)] { return [] }
//        }
//
//        let delta = try update(root: RootPackage(), find: { _ -> Package? in return nil })
//
//        XCTAssertTrue(delta.upgraded.isEmpty)
//        XCTAssertTrue(delta.added.isEmpty)
//        XCTAssertTrue(delta.removed.isEmpty)
//        XCTAssertTrue(delta.downgraded.isEmpty)
//    }
//
//    func testBump() throws {
//        class Package: Update.Package {
//            let url = ""
//            var version = Version(1,0,0)
//
//            func upgrade(to: Version) throws { version = to }
//            func fetch() throws -> [Version] { return [Version(1,0,0), Version(1,0,1), Version(1,0,2)] }
//            func deps() -> [(URL, Range<Version>)] { return [] }
//        }
//
//        let pkg = Package()
//
//        class RootPackage: Update.Parent {
//            func deps() -> [(URL, Range<Version>)] { return [("mock", "1.0.0"..."1.0.2")] }
//        }
//
//        try update(root: RootPackage(), find: { _ in return pkg })
//        XCTAssertEqual(pkg.version, Version(1,0,2))
//    }
//
//    func testConstrainedBump() throws {
//        class Package: Update.Package {
//            let url = ""
//            var version = Version(1,0,0)
//
//            func upgrade(to: Version) throws { version = to }
//            func fetch() throws -> [Version] { return [Version(1,0,0), Version(1,0,1), Version(1,0,2)] }
//            func deps() -> [(URL, Range<Version>)] { return [] }
//        }
//
//        class RootPackage: Update.Parent {
//            func deps() -> [(URL, Range<Version>)] { return [("mock", "1.0.0"..."1.0.1")] }
//        }
//
//        let a = Package()
//        XCTAssertEqual(a.version, Version(1,0,0))
//        try update(root: RootPackage(), find: { _ in return a })
//        XCTAssertEqual(a.version, Version(1,0,1))
//    }
//
//    func testNestedBump() throws {
//        class Package: Update.Package {
//            let url = ""
//            var version = Version(1,0,0)
//
//            func upgrade(to: Version) throws { version = to }
//            func fetch() throws -> [Version] { return [Version(1,0,0), Version(1,0,1), Version(1,0,2)] }
//            func deps() -> [(URL, Range<Version>)] { return [] }
//        }
//    }

//    func testMultipleConstraints() {
//        class Package: Update.Package {
//            init(url: String) {
//                self.url = url
//            }
//
//            let url: String
//            var version = Version(1,0,0)
//
//            func upgrade(to: Version) throws { version = to }
//            func fetch() throws -> [Version] { return [Version(1,0,0), Version(1,0,1), Version(1,0,2)] }
//            func deps() -> [(URL, Range<Version>)] {
//                switch url {
//                case "A":
//                    return [("C", "1.0.0"..."1.0.8")]
//                case "B":
//                    return [("C", "1.0.0"..."1.0.3")]
//                }
//            }
//        }
//
//        class RootPackage {
//            func deps() -> [(URL, Range<Version>)] {
//                return [
//                    ("A", "1.0.0"..."1.0.2"),
//                    ("B", "1.0.0"..."1.0.2")
//                ]
//            }
//        }
//    }
}
