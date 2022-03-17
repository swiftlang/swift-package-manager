//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageDescription
import XCTest

class VersionTests: XCTestCase {
    
    func testVersionInitialization() {
        let v0 = Version(0, 0, 0, prereleaseIdentifiers: [], buildMetadataIdentifiers: [])
        XCTAssertEqual(v0.minor, 0)
        XCTAssertEqual(v0.minor, 0)
        XCTAssertEqual(v0.patch, 0)
        XCTAssertEqual(v0.prereleaseIdentifiers, [])
        XCTAssertEqual(v0.buildMetadataIdentifiers, [])
        
        let v1 = Version(1, 1, 2, prereleaseIdentifiers: ["3", "5"], buildMetadataIdentifiers: ["8", "13"])
        XCTAssertEqual(v1.minor, 1)
        XCTAssertEqual(v1.minor, 1)
        XCTAssertEqual(v1.patch, 2)
        XCTAssertEqual(v1.prereleaseIdentifiers, ["3", "5"])
        XCTAssertEqual(v1.buildMetadataIdentifiers, ["8", "13"])
        
        XCTAssertEqual(
            Version(3, 5, 8),
            Version(3, 5, 8, prereleaseIdentifiers: [], buildMetadataIdentifiers: [])
        )
        
        XCTAssertEqual(
            Version(13, 21, 34, prereleaseIdentifiers: ["55"]),
            Version(13, 21, 34, prereleaseIdentifiers: ["55"], buildMetadataIdentifiers: [])
        )
        
        XCTAssertEqual(
            Version(89, 144, 233, buildMetadataIdentifiers: ["377"]),
            Version(89, 144, 233, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["377"])
        )
    }
    
    // Don't refactor out either `XCTAssertGreaterThan` or `XCTAssertFalse(<)`.
    // They may appear redundant, but they test different things.
    // `XCTAssertGreaterThan` tests the "true" path of `>` which is basically the "true" path of `<`.
    // `XCTAssertFalse(<)` tests the "false" path of `<`.
    func testVersionComparison() {
        
        // MARK: version core vs. version core
        
        XCTAssertGreaterThan(Version(2, 1, 1), Version(1, 2, 3))
        XCTAssertGreaterThan(Version(1, 3, 1), Version(1, 2, 3))
        XCTAssertGreaterThan(Version(1, 2, 4), Version(1, 2, 3))
        
        XCTAssertFalse(Version(2, 1, 1) < Version(1, 2, 3))
        XCTAssertFalse(Version(1, 3, 1) < Version(1, 2, 3))
        XCTAssertFalse(Version(1, 2, 4) < Version(1, 2, 3))
        
        // MARK: version core vs. version core + pre-release
        
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: [""]))
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 2), Version(1, 2, 3, prereleaseIdentifiers: ["beta"]))
        
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: [""]))
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: ["beta"]))
        
        // MARK: version core + pre-release vs. version core + pre-release
        
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: [""]), Version(1, 2, 3, prereleaseIdentifiers: [""]))
        
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta"]), Version(1, 2, 3, prereleaseIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, prereleaseIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha1"]), Version(1, 2, 3, prereleaseIdentifiers: ["alpha2"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, prereleaseIdentifiers: ["alpha-"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"]), Version(1, 2, 3, prereleaseIdentifiers: ["beta", "beta"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha", "beta"]), Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"]))
        
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["1"]), Version(1, 2, 3, prereleaseIdentifiers: ["1"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["1"]), Version(1, 2, 3, prereleaseIdentifiers: ["2"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["1", "1"]), Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"]), Version(1, 2, 3, prereleaseIdentifiers: ["2", "1"]))
        
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["123"]), Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["223"]), Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"]))
        
        // MARK: version core vs. version core + build metadata
        
        XCTAssertEqual(Version(1, 2, 3), Version(1, 2, 3, buildMetadataIdentifiers: [""]))
        XCTAssertEqual(Version(1, 2, 3), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 2), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        
        // MARK: version core + pre-release vs. version core + build metadata
        
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: [""]), Version(1, 2, 3, buildMetadataIdentifiers: [""]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["beta"]), Version(1, 2, 3, buildMetadataIdentifiers: ["alpha"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["beta"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["alpha-"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["123"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["223"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["223"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["223"]))
        XCTAssertLessThan(Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertGreaterThan(Version(2, 2, 3, prereleaseIdentifiers: [""]), Version(1, 2, 3, buildMetadataIdentifiers: [""]))
        XCTAssertGreaterThan(Version(1, 3, 3, prereleaseIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertGreaterThan(Version(1, 2, 4, prereleaseIdentifiers: ["223"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        
        XCTAssertFalse(Version(2, 2, 3, prereleaseIdentifiers: [""]) < Version(1, 2, 3, buildMetadataIdentifiers: [""]))
        XCTAssertFalse(Version(1, 3, 3, prereleaseIdentifiers: ["alpha"]) < Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertFalse(Version(1, 2, 4, prereleaseIdentifiers: ["223"]) < Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        
        // MARK: version core + build metadata vs. version core + build metadata
        
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: [""]), Version(1, 2, 3, buildMetadataIdentifiers: [""]))
        
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["alpha1"]), Version(1, 2, 3, buildMetadataIdentifiers: ["alpha2"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["alpha-"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "alpha"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "beta"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["alpha", "beta"]), Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "alpha"]))
        
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["1"]), Version(1, 2, 3, buildMetadataIdentifiers: ["1"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["1"]), Version(1, 2, 3, buildMetadataIdentifiers: ["2"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["1", "1"]), Version(1, 2, 3, buildMetadataIdentifiers: ["1", "2"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["1", "2"]), Version(1, 2, 3, buildMetadataIdentifiers: ["2", "1"]))
        
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["123"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["223"]), Version(1, 2, 3, buildMetadataIdentifiers: ["123alpha"]))
        
        // MARK: version core vs. version core + pre-release + build metadata
        
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""]))
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: ["123alpha"]))
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: ["alpha"], buildMetadataIdentifiers: ["alpha"]))
        XCTAssertGreaterThan(Version(1, 2, 3), Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["123"]))
        XCTAssertLessThan(Version(1, 2, 2), Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["alpha", "beta"]))
        XCTAssertLessThan(Version(1, 2, 2), Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["alpha-"]))
        
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""]))
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: ["123alpha"]))
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: ["alpha"], buildMetadataIdentifiers: ["alpha"]))
        XCTAssertFalse(Version(1, 2, 3) < Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["123"]))
        
        // MARK: version core + pre-release vs. version core + pre-release + build metadata
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: [""]),
            Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""])
        )
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: [""])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["123alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha1"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha2"], buildMetadataIdentifiers: ["alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha-"], buildMetadataIdentifiers: ["alpha", "beta"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "beta"], buildMetadataIdentifiers: ["123"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha", "beta"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"], buildMetadataIdentifiers: ["alpha-"])
        )
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: ["1"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["1"], buildMetadataIdentifiers: [""])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["2"], buildMetadataIdentifiers: ["123alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "1"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"], buildMetadataIdentifiers: ["123"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["2", "1"], buildMetadataIdentifiers: ["alpha", "beta"])
        )
        
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["123"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"], buildMetadataIdentifiers: ["-alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["223"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"], buildMetadataIdentifiers: ["123"])
        )
        
        // MARK: version core + pre-release + build metadata vs. version core + pre-release + build metadata
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""]),
            Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""])
        )
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["123"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: [""])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha"], buildMetadataIdentifiers: ["-alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["123alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha1"], buildMetadataIdentifiers: ["alpha", "beta"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha2"], buildMetadataIdentifiers: ["alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha"], buildMetadataIdentifiers: ["123"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha-"], buildMetadataIdentifiers: ["alpha", "beta"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"], buildMetadataIdentifiers: ["123alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "beta"], buildMetadataIdentifiers: ["123"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifiers: [""]),
            Version(1, 2, 3, prereleaseIdentifiers: ["beta", "alpha"], buildMetadataIdentifiers: ["alpha-"])
        )
        
        XCTAssertEqual(
            Version(1, 2, 3, prereleaseIdentifiers: ["1"], buildMetadataIdentifiers: ["alpha-"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["1"], buildMetadataIdentifiers: [""])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1"], buildMetadataIdentifiers: ["123"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["2"], buildMetadataIdentifiers: ["123alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "1"], buildMetadataIdentifiers: ["alpha", "beta"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"], buildMetadataIdentifiers: ["123"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["1", "2"], buildMetadataIdentifiers: ["alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["2", "1"], buildMetadataIdentifiers: ["alpha", "beta"])
        )
        
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["123"], buildMetadataIdentifiers: ["123alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"], buildMetadataIdentifiers: ["-alpha"])
        )
        XCTAssertLessThan(
            Version(1, 2, 3, prereleaseIdentifiers: ["223"], buildMetadataIdentifiers: ["123alpha"]),
            Version(1, 2, 3, prereleaseIdentifiers: ["123alpha"], buildMetadataIdentifiers: ["123"])
        )
        
    }
    
    func testCustomConversionFromVersionToString() {
        
        // MARK: Version.description
        
        XCTAssertEqual(Version(0, 0, 0).description, "0.0.0" as String)
        XCTAssertEqual(Version(1, 2, 3).description, "1.2.3" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: [""]).description, "1.2.3-" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["", ""]).description, "1.2.3-." as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta1"]).description, "1.2.3-beta1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "1"]).description, "1.2.3-beta.1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "", "1"]).description, "1.2.3-beta..1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["be-ta", "", "1"]).description, "1.2.3-be-ta..1" as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: [""]).description, "1.2.3+" as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["", ""]).description, "1.2.3+." as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["beta1"]).description, "1.2.3+beta1" as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "1"]).description, "1.2.3+beta.1" as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "", "1"]).description, "1.2.3+beta..1" as String)
        XCTAssertEqual(Version(1, 2, 3, buildMetadataIdentifiers: ["be-ta", "", "1"]).description, "1.2.3+be-ta..1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""]).description, "1.2.3-+" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["", ""], buildMetadataIdentifiers: ["", "-", ""]).description, "1.2.3-.+.-." as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta1"], buildMetadataIdentifiers: ["alpha1"]).description, "1.2.3-beta1+alpha1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "1"], buildMetadataIdentifiers: ["alpha", "1"]).description, "1.2.3-beta.1+alpha.1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "", "1"], buildMetadataIdentifiers: ["alpha", "", "1"]).description, "1.2.3-beta..1+alpha..1" as String)
        XCTAssertEqual(Version(1, 2, 3, prereleaseIdentifiers: ["be-ta", "", "1"], buildMetadataIdentifiers: ["al-pha", "", "1"]).description, "1.2.3-be-ta..1+al-pha..1" as String)
        
        // MARK: String interpolation
        
        XCTAssertEqual("\(Version(0, 0, 0))", "0.0.0" as String)
        XCTAssertEqual("\(Version(1, 2, 3))", "1.2.3" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: [""]))", "1.2.3-" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["", ""]))", "1.2.3-." as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta1"]))", "1.2.3-beta1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "1"]))", "1.2.3-beta.1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "", "1"]))", "1.2.3-beta..1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["be-ta", "", "1"]))", "1.2.3-be-ta..1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: [""]))", "1.2.3+" as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: ["", ""]))", "1.2.3+." as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: ["beta1"]))", "1.2.3+beta1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "1"]))", "1.2.3+beta.1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: ["beta", "", "1"]))", "1.2.3+beta..1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, buildMetadataIdentifiers: ["be-ta", "", "1"]))", "1.2.3+be-ta..1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: [""], buildMetadataIdentifiers: [""]))", "1.2.3-+" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["", ""], buildMetadataIdentifiers: ["", "-", ""]))", "1.2.3-.+.-." as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta1"], buildMetadataIdentifiers: ["alpha1"]))", "1.2.3-beta1+alpha1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "1"], buildMetadataIdentifiers: ["alpha", "1"]))", "1.2.3-beta.1+alpha.1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["beta", "", "1"], buildMetadataIdentifiers: ["alpha", "", "1"]))", "1.2.3-beta..1+alpha..1" as String)
        XCTAssertEqual("\(Version(1, 2, 3, prereleaseIdentifiers: ["be-ta", "", "1"], buildMetadataIdentifiers: ["al-pha", "", "1"]))", "1.2.3-be-ta..1+al-pha..1" as String)
        
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
    
    func testExpressingVersionByStringLiteral() {
        
        // MARK: Well-formed version core
        
        XCTAssertEqual("0.0.0" as Version, Version(0, 0, 0))
        XCTAssertEqual("1.1.2" as Version, Version(1, 1, 2))
        
        // MARK: Malformed version core
        
        XCTAssertEqual("" as Version, Version(0, 0, 0))
        XCTAssertEqual("3" as Version, Version(0, 0, 0))
        XCTAssertEqual("3 5" as Version, Version(0, 0, 0))
        XCTAssertEqual("5.8" as Version, Version(0, 0, 0))
        XCTAssertEqual("-5.8.13" as Version, Version(0, 0, 0))
        XCTAssertEqual("8.-13.21" as Version, Version(0, 0, 0))
        XCTAssertEqual("13.21.-34" as Version, Version(0, 0, 0))
        XCTAssertEqual("-0.0.0" as Version, Version(0, 0, 0))
        XCTAssertEqual("0.-0.0" as Version, Version(0, 0, 0))
        XCTAssertEqual("0.0.-0" as Version, Version(0, 0, 0))
        XCTAssertEqual("21.34.55.89" as Version, Version(0, 0, 0))
        XCTAssertEqual("6 x 9 = 42" as Version, Version(0, 0, 0))
        XCTAssertEqual("forty two" as Version, Version(0, 0, 0))
        
        // MARK: Well-formed version core, well-formed pre-release identifiers
        
        XCTAssertEqual("0.0.0-pre-alpha" as Version, Version(0, 0, 0, prereleaseIdentifiers: ["pre-alpha"]))
        XCTAssertEqual("55.89.144-beta.1" as Version, Version(55, 89, 144, prereleaseIdentifiers: ["beta", "1"]))
        XCTAssertEqual("89.144.233-a.whole..lot.of.pre-release.identifiers" as Version, Version(89, 144, 233, prereleaseIdentifiers: ["a", "whole", "", "lot", "of", "pre-release", "identifiers"]))
        XCTAssertEqual("144.233.377-" as Version, Version(144, 233, 377, prereleaseIdentifiers: [""]))
        
        // MARK: Well-formed version core, malformed pre-release identifiers
        
        XCTAssertEqual("233.377.610-hello world" as Version, Version(0, 0, 0))
        
        // MARK: Malformed version core, well-formed pre-release identifiers
        
        XCTAssertEqual("-Hello.world--------" as Version, Version(0, 0, 0))
        XCTAssertEqual("987-Hello.world--------" as Version, Version(0, 0, 0))
        XCTAssertEqual("987.1597-half-life.3" as Version, Version(0, 0, 0))
        XCTAssertEqual("1597.2584.4181.6765-a.whole.lot.of.pre-release.identifiers" as Version, Version(0, 0, 0))
        XCTAssertEqual("6 x 9 = 42-" as Version, Version(0, 0, 0))
        XCTAssertEqual("forty-two" as Version, Version(0, 0, 0))
        
        // MARK: Well-formed version core, well-formed build metadata identifiers
        
        XCTAssertEqual("0.0.0+some-metadata" as Version, Version(0, 0, 0, buildMetadataIdentifiers: ["some-metadata"]))
        XCTAssertEqual("4181.6765.10946+more.meta..more.data" as Version, Version(4181, 6765, 10946, buildMetadataIdentifiers: ["more", "meta", "", "more", "data"]))
        XCTAssertEqual("6765.10946.17711+-a-very--long---build-----metadata--------identifier-------------with---------------------many----------------------------------hyphens-------------------------------------------------------" as Version, Version(6765, 10946, 17711, buildMetadataIdentifiers: ["-a-very--long---build-----metadata--------identifier-------------with---------------------many----------------------------------hyphens-------------------------------------------------------"]))
        XCTAssertEqual("10946.17711.28657+" as Version, Version(10946, 17711, 28657, buildMetadataIdentifiers: [""]))
        
        // MARK: Well-formed version core, malformed build metadata identifiers
        
        XCTAssertEqual("17711.28657.46368+hello world" as Version, Version(0, 0, 0))
        XCTAssertEqual("28657.46368.75025+hello+world" as Version, Version(0, 0, 0))
        
        // MARK: Malformed version core, well-formed build metadata identifiers
        
        XCTAssertEqual("+Hello.world--------" as Version, Version(0, 0, 0))
        XCTAssertEqual("121393+Hello.world--------" as Version, Version(0, 0, 0))
        XCTAssertEqual("121393.196418+half-life.3" as Version, Version(0, 0, 0))
        XCTAssertEqual("196418.317811.514229.832040+a.whole.lot.of.build.metadata.identifiers" as Version, Version(0, 0, 0))
        XCTAssertEqual("196418.317811.514229.832040+a.whole.lot.of.build.metadata.identifiers" as Version, Version(0, 0, 0))
        XCTAssertEqual("6 x 9 = 42+" as Version, Version(0, 0, 0))
        XCTAssertEqual("forty two+a-very-long-build-metadata-identifier-with-many-hyphens" as Version, Version(0, 0, 0))
        
        // MARK: Well-formed version core, well-formed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertEqual("0.0.0-beta.-42+42-42.42" as Version, Version(0, 0, 0, prereleaseIdentifiers: ["beta", "-42"], buildMetadataIdentifiers: ["42-42", "42"]))
        
        // MARK: Well-formed version core, well-formed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertEqual("514229.832040.1346269-beta1+  " as Version, Version(0, 0, 0))
        
        // MARK: Well-formed version core, malformed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertEqual("832040.1346269.2178309-beta 1+-" as Version, Version(0, 0, 0))
        
        // MARK: Well-formed version core, malformed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertEqual("1346269.2178309.3524578-beta 1++" as Version, Version(0, 0, 0))
        
        // MARK: malformed version core, well-formed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertEqual(" 832040.1346269.3524578-beta1+abc" as Version, Version(0, 0, 0))
        
        // MARK: malformed version core, well-formed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertEqual("1346269.3524578.5702887-beta1+😀" as Version, Version(0, 0, 0))
        
        // MARK: malformed version core, malformed pre-release identifiers, well-formed build metadata identifiers
        
        XCTAssertEqual("3524578.5702887.9227465-beta!@#$%^&*1+asdfghjkl123456789" as Version, Version(0, 0, 0))
        
        // MARK: malformed version core, malformed pre-release identifiers, malformed build metadata identifiers
        
        XCTAssertEqual("5702887.9227465-bètá1+±" as Version, Version(0, 0, 0))
        
    }
    
    // A semantic version string is always longer than 1 character, so the only way to test these 2 initializers is by calling them directly.
    
    func testExpressingVersionByExtendedGraphemeClusterLiteral() {
        XCTAssertEqual(Version(extendedGraphemeClusterLiteral: "版⃣"), Version(0, 0, 0))
    }
    
    func testExpressingVersionByUnicodeScalarLiteral() {
        XCTAssertEqual(Version(unicodeScalarLiteral: "a"), Version(0, 0, 0))
    }
    
}

