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

class PackageIdentityNameTests: XCTestCase {
    func testValidNames() throws {
        XCTAssertNoThrow(try PackageIdentity.Name(validating: "LinkedList"))
        XCTAssertNoThrow(try PackageIdentity.Name(validating: "Linked-List"))
        XCTAssertNoThrow(try PackageIdentity.Name(validating: "Linked_List"))
        XCTAssertNoThrow(try PackageIdentity.Name(validating: "A"))
        XCTAssertNoThrow(try PackageIdentity.Name(validating: "1"))
        XCTAssertNoThrow(try PackageIdentity.Name(validating: String(repeating: "A", count: 100)))
    }

    func testInvalidNames() throws {
        XCTAssertThrowsError(try PackageIdentity.Name(validating: "")) { error in
            XCTAssertEqual(error.localizedDescription, "The minimum length of a package name is 1 character.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: String(repeating: "a", count: 101))) { error in
            XCTAssertEqual(error.localizedDescription, "The maximum length of a package name is 100 characters.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "!")) { error in
            XCTAssertEqual(error.localizedDescription, "A package name consists of alphanumeric characters, underscores, and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "あ")) { error in
            XCTAssertEqual(error.localizedDescription, "A package name consists of alphanumeric characters, underscores, and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "🧍")) { error in
            XCTAssertEqual(error.localizedDescription, "A package name consists of alphanumeric characters, underscores, and hyphens.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "-a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur at the beginning of a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "_a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur at the beginning of a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a-")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur at the end of a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a_")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur at the end of a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a_-a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur consecutively within a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a-_a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur consecutively within a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a--a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur consecutively within a name.")
        }

        XCTAssertThrowsError(try PackageIdentity.Name(validating: "a__a")) { error in
            XCTAssertEqual(error.localizedDescription, "Hyphens and underscores may not occur consecutively within a name.")
        }
    }

    func testNamesAreCaseInsensitive() throws {
        let lowercase: PackageIdentity.Name = "linkedlist"
        let uppercase: PackageIdentity.Name = "LINKEDLIST"

        XCTAssertEqual(lowercase, uppercase)
    }
}
