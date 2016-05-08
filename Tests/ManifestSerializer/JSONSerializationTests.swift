/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import ManifestSerializer
import PackageDescription
import XCTest

class JSONSerializationTests: XCTestCase {
    
    func testSimple() {
        let package = Package(name: "Simple")
        let exp = NSMutableDictionary.withNew { (dict) in
            dict["name"] = "Simple"
            fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", "package.targets"], dict: dict)
        }
        assertEqual(package: package, expected: exp)
    }
    
    //FIXME: more tests to come
}

extension JSONSerializationTests {
    
    func fillWithEmptyArrays(keyNames: [String], dict: NSMutableDictionary) {
        keyNames.forEach {
            dict[$0] = NSArray()
        }
    }
    
    func assertEqual(package: Package, expected: NSMutableDictionary) {
        let json = package.toJSON() as! NSMutableDictionary
        XCTAssertEqual(json, expected)
    }
}

extension JSONSerializationTests {
    static var allTests : [(String, (JSONSerializationTests) -> () throws -> Void)] {
        return [
            ("testSimple", testSimple),
        ]
    }
}
