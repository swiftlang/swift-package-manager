/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription
import XCTest

class VersionTests: XCTestCase {

    func testBasics() {
        let v1: Version = "1.0.0"
        let v2 = Version(2, 3, 4, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifiers: ["232"])
        XCTAssert(v2 > v1)
        XCTAssertFalse(v2 == v1)
        XCTAssert("1.0.0" == v1)
        XCTAssertLessThan(Version("1.2.3-alpha.beta.2"), Version("1.2.3-alpha.beta.3"))

        XCTAssertEqual(Version("1.2.3-alpha.beta.2").description, "1.2.3-alpha.beta.2")
    }
    
        
        
        
    func testLosslessConversionFromStringToVersion() {
        
        // We use type coercion `as String` in `Version(_:)` because there is a pair of overloaded initializers: `init(_ version: Version)` and `init?(_ versionString: String)`, and we want to test the latter in this function.
        
        // MARK: Well-formed version core
        
        XCTAssertNotNil(Version("0.0.0" as String))
        XCTAssertEqual(Version("0.0.0" as String), Version(0, 0, 0))

        XCTAssertNotNil(Version("1.1.2" as String))
        XCTAssertEqual(Version("1.1.2" as String), Version(1, 1, 2))

        // MARK: Malformed version core

        XCTAssertNil(Version("3" as String))
        XCTAssertNil(Version("3 5" as String))
        XCTAssertNil(Version("5.8" as String))
        XCTAssertNil(Version("-5.8.13" as String))
        XCTAssertNil(Version("8.-13.21" as String))
        XCTAssertNil(Version("13.21.-34" as String))
        XCTAssertNil(Version("-0.0.0" as String))
        XCTAssertNil(Version("0.-0.0" as String))
        XCTAssertNil(Version("0.0.-0" as String))
        XCTAssertNil(Version("21.34.55.89" as String))
        XCTAssertNil(Version("6 x 9 = 42" as String))
        XCTAssertNil(Version("forty two" as String))

        // MARK: Well-formed version core, well-formed pre-release identifiers

        XCTAssertNotNil(Version("0.0.0-pre-alpha" as String))
        XCTAssertEqual(Version("0.0.0-pre-alpha" as String), Version(0, 0, 0, prereleaseIdentifiers: ["pre-alpha"]))

        XCTAssertNotNil(Version("55.89.144-beta.1" as String))
        XCTAssertEqual(Version("55.89.144-beta.1" as String), Version(55, 89, 144, prereleaseIdentifiers: ["beta", "1"]))
        
        XCTAssertNotNil(Version("89.144.233-a.whole..lot.of.pre-release.identifiers" as String))
        XCTAssertEqual(Version("89.144.233-a.whole..lot.of.pre-release.identifiers" as String), Version(89, 144, 233, prereleaseIdentifiers: ["a", "whole", "", "lot", "of", "pre-release", "identifiers"]))

        XCTAssertNotNil(Version("144.233.377-" as String))
        XCTAssertEqual(Version("144.233.377-" as String), Version(144, 233, 377, prereleaseIdentifiers: [""]))

        // MARK: Well-formed version core, malformed pre-release identifiers
        
        XCTAssertNil(Version("233.377.610-hello world" as String))

        // MARK: Malformed version core, well-formed pre-release identifiers

        XCTAssertNil(Version("987-Hello.world--------" as String))
        XCTAssertNil(Version("987.1597-half-life.3" as String))
        XCTAssertNil(Version("1597.2584.4181.6765-a.whole.lot.of.pre-release.identifiers" as String))
        XCTAssertNil(Version("6 x 9 = 42-" as String))
        XCTAssertNil(Version("forty-two" as String))
//
        // MARK: Well-formed version core, well-formed build metadata identifiers
        
        XCTAssertNotNil(Version("0.0.0+some-metadata" as String))
        XCTAssertEqual(Version("0.0.0+some-metadata" as String), Version(0, 0, 0, buildMetadataIdentifiers: ["some-metadata"]))
        
        XCTAssertNotNil(Version("4181.6765.10946+more.meta..more.data" as String))
        XCTAssertEqual(Version("4181.6765.10946+more.meta..more.data" as String), Version(4181, 6765, 10946, buildMetadataIdentifiers: ["more", "meta", "", "more", "data"]))
        
        XCTAssertNotNil(Version("6765.10946.17711+-a-very--long---build-----metadata--------identifier-------------with---------------------many----------------------------------hyphens-------------------------------------------------------" as String))
        XCTAssertEqual(Version("6765.10946.17711+-a-very--long---build-----metadata--------identifier-------------with---------------------many----------------------------------hyphens-------------------------------------------------------" as String), Version(6765, 10946, 17711, buildMetadataIdentifiers: ["-a-very--long---build-----metadata--------identifier-------------with---------------------many----------------------------------hyphens-------------------------------------------------------"]))
        
        XCTAssertNotNil(Version("10946.17711.28657+" as String))
        XCTAssertEqual(Version("10946.17711.28657+" as String), Version(10946, 17711, 28657, buildMetadataIdentifiers: [""]))
        
        // MARK: Well-formed version core, malformed build metadata identifiers
        
        XCTAssertNil(Version("17711.28657.46368+hello world" as String))
        XCTAssertNil(Version("28657.46368.75025+hello+world" as String))
        
        // MARK: Malformed version core, well-formed build metadata identifiers
        
        XCTAssertNil(Version("121393+Hello.world--------" as String))
        XCTAssertNil(Version("121393.196418+half-life.3" as String))
        XCTAssertNil(Version("196418.317811.514229.832040+a.whole.lot.of.build.metadata.identifiers" as String))
        XCTAssertNil(Version("196418.317811.514229.832040+a.whole.lot.of.build.metadata.identifiers" as String))
        XCTAssertNil(Version("6 x 9 = 42+" as String))
        XCTAssertNil(Version("forty two+a-very-long-build-metadata-identifier-with-many-hyphens" as String))
        
        // MARK: Well-formed version core, well-formed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertNotNil(Version("0.0.0-beta.-42+42-42.42" as String))
        XCTAssertEqual(Version("0.0.0-beta.-42+42-42.42" as String), Version(0, 0, 0, prereleaseIdentifiers: ["beta", "-42"], buildMetadataIdentifiers: ["42-42", "42"]))
        
        // MARK: Well-formed version core, well-formed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertNil(Version("514229.832040.1346269-beta1+  " as String))
        
        // MARK: Well-formed version core, malformed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertNil(Version("832040.1346269.2178309-beta 1+-" as String))
        
        // MARK: Well-formed version core, malformed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertNil(Version("1346269.2178309.3524578-beta 1++" as String))
        
        // MARK: malformed version core, well-formed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertNil(Version(" 832040.1346269.3524578-beta1+abc" as String))
        
        // MARK: malformed version core, well-formed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertNil(Version("1346269.3524578.5702887-beta1+😀" as String))
        
        // MARK: malformed version core, malformed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertNil(Version("3524578.5702887.9227465-beta!@#$%^&*1+asdfghjkl123456789" as String))
        
        // MARK: malformed version core, malformed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertNil(Version("5702887.9227465-bètá1+±" as String))
        
    }
}

