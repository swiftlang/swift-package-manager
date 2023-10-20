//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

@testable import PackageModel

final class InstalledSwiftPMConfigurationTests: XCTestCase {
    func testVersionDescription() {
        do {
            let version = InstalledSwiftPMConfiguration.Version(major: 509, minor: 0, patch: 0)
            XCTAssertEqual(version.description, "509.0.0")
        }
        do {
            let version = InstalledSwiftPMConfiguration.Version(major: 509, minor: 0, patch: 0, prereleaseIdentifier: "alpha1")
            XCTAssertEqual(version.description, "509.0.0-alpha1")
        }
        do {
            let version = InstalledSwiftPMConfiguration.Version(major: 509, minor: 0, patch: 0, prereleaseIdentifier: "beta.1")
            XCTAssertEqual(version.description, "509.0.0-beta.1")
        }
    }
}
