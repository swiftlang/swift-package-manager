//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import Basics
import PackageModel

class PackageIdentityScopeTests: XCTestCase {
    func testValidScopes() throws {
        XCTAssertNoThrow(try PackageIdentity.Scope(validating: "mona"))
        XCTAssertNoThrow(try PackageIdentity.Scope(validating: "m-o-n-a"))
        XCTAssertNoThrow(try PackageIdentity.Scope(validating: "a"))
        XCTAssertNoThrow(try PackageIdentity.Scope(validating: "1"))
        XCTAssertNoThrow(try PackageIdentity.Scope(validating: String(repeating: "a", count: 39)))
    }

    func testInvalidScopes() throws {
        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "")) { error in
            XCTAssertEqual(error.localizedDescription, "The minimum length of a package scope is 1 character.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: String(repeating: "a", count: 100))) { error in
            XCTAssertEqual(error.localizedDescription, "The maximum length of a package scope is 39 characters.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "!")) { error in
            XCTAssertEqual(error.localizedDescription, "A package scope consists of alphanumeric characters and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "あ")) { error in
            XCTAssertEqual(error.localizedDescription, "A package scope consists of alphanumeric characters and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "🧍")) { error in
            XCTAssertEqual(error.localizedDescription, "A package scope consists of alphanumeric characters and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "-a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens may not occur at the beginning of a scope.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "a-")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens may not occur at the end of a scope.")
        }

        XCTAssertThrowsError(try PackageIdentity.Scope(validating: "a--a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens may not occur consecutively within a scope.")
        }
    }

    func testScopesAreCaseInsensitive() throws {
        let lowercase: PackageIdentity.Scope = "mona"
        let uppercase: PackageIdentity.Scope = "MONA"

        XCTAssertEqual(lowercase, uppercase)
    }
}
